# Reproduction Runbook (Assessor-Friendly)

This repo is structured so an assessor can reproduce the deployment by running the included scripts, then verify using the provided commands (no secrets printed).

Scope: you can use an **existing EKS cluster**, or create one using `eksctl` (included below). Creating EKS resources costs money; delete the cluster when finished.

## 0) Prereqs (Local)

Required tools:
- `aws`, `kubectl`, `helm`, `jq`, `python3`
- Optional (for cluster creation): `eksctl`
- Terraform: `terraform` must be available in `PATH`

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

If you already have a cluster, skip this.

Destroy when finished:
```bash
infra/eksctl/delete-cluster.sh
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

Create the EFS-backed PV/PVC (`openedx-media`) in `openedx-prod`:
```bash
infra/k8s/02-storage/apply.sh
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

## 6) HPA + Load Test

Apply HPA + resource requests/limits:
```bash
infra/k8s/05-hpa/apply.sh
kubectl -n openedx-prod get hpa
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
          args: ["run", "/scripts/loadtest-k6.js"]
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

## 9) Backups

EBS + RDS snapshots (script does not print secrets):
```bash
infra/backups/backup.sh
```

EFS media backup strategy: `docs/backup-restore.md`.

## 10) Evidence Pack

Follow the ordered checklist:
- `docs/evidence-checklist.md`
