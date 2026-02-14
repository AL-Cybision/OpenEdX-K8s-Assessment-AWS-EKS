# Reproduction Runbook (Assessor-Friendly)

This repo is structured so an assessor can reproduce the deployment by running the included scripts, then verify using the provided commands (no secrets printed).

Scope: you can use an **existing EKS cluster**, or create one using `eksctl` (included below). Creating EKS resources costs money; delete the cluster when finished.

## 0) Prereqs (Local)

Required tools:
- `aws`, `kubectl`, `helm`, `jq`, `python3`
- `eksctl` (for cluster creation and core add-ons script)
- Terraform: `terraform` must be available in `PATH`
- Security note: Terraform state files (for example `infra/**/terraform.tfstate`) are generated locally and contain secrets. They are `.gitignore`'d; do not commit or share them.

Verify AWS + cluster access:
```bash
aws sts get-caller-identity
aws eks describe-cluster --name openedx-eks --region us-east-1 --query 'cluster.status' --output text
kubectl get ns
```

## 0.1) Optional: Create the EKS Cluster (eksctl)

Cost note: this creates a VPC + a NAT gateway + 2 managed worker nodes, so charges start immediately.

```bash
infra/eksctl/create-cluster.sh
```

Note: by default this also runs `infra/eksctl/install-core-addons.sh` after cluster creation (`INSTALL_CORE_ADDONS=true`).

If you already have a cluster, skip this.

Destroy when finished:
```bash
infra/eksctl/delete-cluster.sh
```

## 0.2) Core Add-ons (Mandatory for this stack)

Install EBS CSI + IAM role, set `gp3` default StorageClass, and install `metrics-server`:
```bash
infra/eksctl/install-core-addons.sh
```

Verify:
```bash
aws eks describe-addon --cluster-name openedx-eks --region us-east-1 --addon-name aws-ebs-csi-driver --query 'addon.status' --output text
kubectl get storageclass
kubectl -n kube-system get deploy metrics-server
kubectl top nodes
```

## 1) Namespaces

```bash
kubectl apply -f k8s/00-namespaces/namespaces.yaml
```

Expected:
```bash
kubectl get ns openedx-prod ingress-nginx observability
```

## 2) Ingress Controller (NGINX)

Install/upgrade:
```bash
infra/ingress-nginx/install.sh
```

Verify:
```bash
helm -n ingress-nginx ls
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

## 3) External Data Layer (Terraform)

Provision RDS MySQL + EC2 Mongo/Redis/Elasticsearch (private only, SG restricted to worker SG):
```bash
infra/terraform/apply.sh
```

Verify (no secrets printed):
```bash
RDS_ENDPOINT=$(terraform -chdir=infra/terraform output -raw rds_endpoint)
aws rds describe-db-instances --region us-east-1 \
  --query "DBInstances[?Endpoint.Address=='${RDS_ENDPOINT}'].[DBInstanceIdentifier,PubliclyAccessible,Engine,EngineVersion]" \
  --output table
```

## 4) Shared Media Storage (EFS RWX)

Provision EFS + EFS CSI driver:
```bash
infra/media-efs/apply.sh
```

Create storage resources in `openedx-prod`:
- Ensures `gp3` is the default StorageClass (EBS CSI baseline)
- Creates the EFS-backed `openedx-media` PV/PVC

```bash
infra/k8s/02-storage/apply.sh
kubectl get storageclass
kubectl -n openedx-prod get pvc openedx-media
```

## 5) Tutor/Open edX Apply (Caddy Removed + Probes + Media Mount)

Assumes Tutor is installed and configured as described in `docs/tutor-k8s.md`.

Apply Tutor manifests using the wrapper (this permanently removes Caddy and injects probes + media mount):
```bash
infra/k8s/04-tutor-apply/apply.sh
```

Apply ingress rules:
```bash
k8s/03-ingress/create-selfsigned-tls.sh
kubectl apply -f k8s/03-ingress/openedx-ingress.yaml
kubectl -n openedx-prod get ingress openedx
```

Fix AuthN/Authoring MFE under HTTPS (required when TLS terminates at NGINX Ingress):
```bash
mkdir -p "${HOME}/.local/share/tutor-plugins"
cp data-layer/tutor/plugins/openedx-mfe-https.py "${HOME}/.local/share/tutor-plugins/openedx-mfe-https.py"
.venv/bin/tutor plugins enable openedx-mfe-https

infra/k8s/04-tutor-apply/apply.sh
```

Verify `mfe` service is internal-only (`ClusterIP`) and not externally exposed via `NodePort`:
```bash
kubectl -n openedx-prod get svc mfe -o jsonpath='{.spec.type}{"\n"}'
```

Browser access (with placeholder domains):
```bash
LB_DNS=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
LB_IP=$(getent ahostsv4 "$LB_DNS" | awk '{print $1; exit}')

# MFE login uses apps.lms.openedx.local, so include it here.
printf "\n# OpenEdX Ingress\n%s lms.openedx.local studio.openedx.local apps.lms.openedx.local\n" "$LB_IP" | sudo tee -a /etc/hosts >/dev/null
```

## 5.1) Studio Course Creation + Persistence Validation (Mandatory)

Create one sample course in Studio:
- Open `https://studio.openedx.local`
- Create a new course (for example `compliance-101`)
- Publish at least one unit/page

Verify MongoDB contains course/modulestore collections (without printing secrets):
```bash
kubectl -n openedx-prod exec deploy/lms -- bash -lc 'cd /openedx/edx-platform && \
python manage.py lms shell --no-imports --command "\
import re; \
from django.conf import settings; \
from pymongo import MongoClient; \
conf=settings.CONTENTSTORE[\"DOC_STORE_CONFIG\"]; \
client=MongoClient(conf[\"host\"], int(conf.get(\"port\", 27017)), \
  username=conf.get(\"user\"), password=conf.get(\"password\"), \
  authSource=conf.get(\"authsource\") or conf.get(\"db\") or \"admin\", \
  tls=bool(conf.get(\"ssl\", False))); \
db=client[conf[\"db\"]]; \
names=[n for n in db.list_collection_names() if re.search(r\"modulestore|course\", n, re.I)]; \
print(names[:20])"'
```

Restart LMS/CMS pods and confirm course still exists:
```bash
kubectl -n openedx-prod rollout restart deploy/lms deploy/cms
kubectl -n openedx-prod rollout status deploy/lms --timeout=10m
kubectl -n openedx-prod rollout status deploy/cms --timeout=10m
```

Re-open LMS/Studio and confirm the same course is still present.

## 6) HPA + Load Test

Apply HPA + resource requests/limits (script validates metrics-server):
```bash
infra/k8s/05-hpa/apply.sh
kubectl -n openedx-prod get hpa
```

If `lms` rollout is blocked due capacity, temporarily scale nodegroup to 3 before load test:
```bash
NODEGROUP=$(aws eks list-nodegroups --cluster-name openedx-eks --region us-east-1 --query 'nodegroups[0]' --output text)
aws eks update-nodegroup-config \
  --cluster-name openedx-eks \
  --nodegroup-name "${NODEGROUP}" \
  --region us-east-1 \
  --scaling-config minSize=2,maxSize=3,desiredSize=3
```

Run k6 load test (in-cluster):
```bash
kubectl -n openedx-prod create configmap k6-script \
  --from-file=loadtest-k6.js=infra/k8s/05-hpa/loadtest-k6.js \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n openedx-prod delete job k6-loadtest --ignore-not-found
kubectl -n openedx-prod apply -f - <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-loadtest
  namespace: openedx-prod
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: k6
          image: grafana/k6:0.49.0
          args: ["run", "--vus", "120", "--duration", "5m", "/scripts/loadtest-k6.js"]
          volumeMounts:
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: scripts
          configMap:
            name: k6-script
YAML
```

Watch scaling:
```bash
kubectl -n openedx-prod get hpa -w
```

## 7) Observability (Prometheus/Grafana + Loki)

```bash
infra/observability/install.sh
kubectl -n observability get pods
```

Access steps and queries: `docs/observability.md`.

Apply custom alerts (optional but included as an alerting configuration artifact):
```bash
infra/observability/apply-alerts.sh
```

## 8) CloudFront + WAF

```bash
infra/cloudfront-waf/apply.sh
infra/cloudfront-waf/verify.sh
```

Rerun note:
- `infra/cloudfront-waf/apply.sh` auto-imports existing OpenEdX CloudFront/WAF resources if local Terraform state is missing, to avoid duplicate-name failures in reused assessor accounts.

Production-hardening option (when ingress has a publicly trusted certificate):
```bash
ORIGIN_PROTOCOL_POLICY=https-only infra/cloudfront-waf/apply.sh
```

## 9) Backups

EBS + RDS snapshots (script does not print secrets):
```bash
infra/backups/backup.sh
```

EFS media backup strategy: `docs/backup-restore.md`.

## 9.1) Email Activation (Professional SMTP via Amazon SES)

If you want learner registration + activation to work end-to-end (activation emails delivered), configure SMTP properly.

This repo ships an SES-based setup that keeps the architecture unchanged:
- Open edX still sends mail to the in-cluster `smtp` service (`smtp:8025`)
- The `smtp` pod (Exim relay) is configured to relay **outbound** via **Amazon SES SMTP (587 + auth)**.

Check SES sandbox status:
```bash
aws sesv2 get-account --region us-east-1 --query '{ProductionAccessEnabled:ProductionAccessEnabled,SendingEnabled:SendingEnabled,SendQuota:SendQuota}' --output json
```

If `ProductionAccessEnabled=false` (sandbox), SES can only send to verified identities.
For testing activation, you can verify your own recipient email address.

Important: the SES identity you verify must match the **From** address that Open edX uses.
By default, Open edX uses `contact@<LMS_HOST>` as `DEFAULT_FROM_EMAIL` (example: `contact@lms.syncummah.com`).

1. Create/ensure SES identities and store SMTP creds in Secrets Manager (no secrets printed).
Recommended (matches the default Open edX from-address pattern):
```bash
REGION=us-east-1 SES_DOMAIN=lms.syncummah.com FROM_EMAIL=contact@lms.syncummah.com VERIFY_RECIPIENT_EMAIL=you@example.com \
  infra/ses/setup.sh
```

This prints the DNS records to add (SES verification TXT + DKIM CNAMEs). Add them in your DNS, then wait until SES shows the identity as verified.

2. Apply SMTP relay config to Kubernetes (use the Secret ARN printed by `setup.sh`):
```bash
REGION=us-east-1 SES_SMTP_SECRET_ID='arn:aws:secretsmanager:us-east-1:...:secret:openedx-prod/ses-smtp-...' infra/ses/apply.sh
kubectl -n openedx-prod logs deploy/smtp --tail=50
```

3. Trigger activation email from the LMS UI by registering a learner account.

Debug tip (verifies relay wiring without exposing secrets):
```bash
kubectl -n openedx-prod exec deploy/lms -c lms -- sh -lc '\
  cd /openedx/edx-platform && \
  /openedx/venv/bin/python manage.py lms shell -c "from django.core.mail import send_mail; send_mail(\"Open edX SES test\",\"hello\",None,[\"you@example.com\"],fail_silently=False); print(\"sent\")"'

kubectl -n openedx-prod logs deploy/smtp --tail=200
```

Production note: to send to arbitrary recipients, request SES production access for your AWS account/region.

## 10) Evidence Pack

Follow the ordered checklist:
- `docs/evidence-checklist.md`
