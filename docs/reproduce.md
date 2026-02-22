# Reproduce (Assessment Runbook)

This runbook is the source of truth for assessors. It uses only the canonical scripts in `scripts/`.

## Prerequisites

- AWS credentials configured for target account
- Region: `us-east-1`
- Tools: `aws`, `kubectl`, `eksctl`, `helm`, `terraform`, `jq`, `curl`, `dig`
- Real DNS records prepared:
  - `lms.<domain>`
  - `studio.<domain>`
  - `apps.lms.<domain>`

## 0) Preflight

```bash
scripts/00-preflight-check.sh
```

## 1) Cluster

Create cluster (skip if already exists):

```bash
scripts/10-eks-create.sh
```

Harden endpoint and install core add-ons:

```bash
scripts/11-eks-harden-endpoint.sh
scripts/12-eks-core-addons.sh
```

## 2) Namespaces + Ingress

```bash
scripts/20-namespaces-apply.sh
scripts/21-ingress-nginx-install.sh
```

## 3) External Data Layer + Storage

```bash
scripts/30-data-layer-apply.sh
scripts/31-media-efs-apply.sh
scripts/32-storage-apply.sh
```

## 4) Open edX Apply

Tutor must already be installed (`.venv/bin/tutor` available).

```bash
scripts/40-openedx-apply.sh
```

## 5) TLS + Real-Domain Ingress

Install cert-manager:

```bash
scripts/23-cert-manager-install.sh
```

Fail-fast DNS check (must resolve to current ingress LB):

```bash
LB_DNS="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "Expected ingress LB: ${LB_DNS}"

dig +short lms.<domain>
dig +short studio.<domain>
dig +short apps.lms.<domain>
```

Apply certificate + ingress:

```bash
TUTOR_BIN=".venv/bin/tutor"
LMS_HOST="$(${TUTOR_BIN} config printvalue LMS_HOST)"
CMS_HOST="$(${TUTOR_BIN} config printvalue CMS_HOST)"
MFE_HOST="apps.${LMS_HOST}"

LETSENCRYPT_EMAIL="you@example.com" \
LMS_HOST="${LMS_HOST}" \
CMS_HOST="${CMS_HOST}" \
MFE_HOST="${MFE_HOST}" \
TLS_SECRET_NAME="openedx-tls" \
INGRESS_NAME="openedx" \
  scripts/41-real-domain-ingress-apply.sh
```

Verify:

```bash
kubectl -n openedx-prod get certificate openedx-tls
kubectl -n openedx-prod get ingress openedx
```

## 6) HPA + Load Testing

```bash
scripts/50-hpa-apply.sh
kubectl -n openedx-prod get hpa
```

Run k6 load job:

```bash
TUTOR_BIN=".venv/bin/tutor"
LMS_HOST="$(${TUTOR_BIN} config printvalue LMS_HOST)"

kubectl -n openedx-prod create configmap k6-script \
  --from-file=loadtest-k6.js=configs/k8s/hpa/loadtest-k6.js \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n openedx-prod delete job k6-loadtest --ignore-not-found

cat <<YAML | kubectl apply -f -
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
          env:
            - name: LMS_HOST
              value: "${LMS_HOST}"
          volumeMounts:
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: scripts
          configMap:
            name: k6-script
YAML

kubectl -n openedx-prod get hpa -w
```

## 7) Observability

```bash
scripts/51-observability-install.sh
kubectl -n observability get pods
```

## 8) CloudFront + WAF

```bash
scripts/52-cloudfront-waf-apply.sh
scripts/53-cloudfront-waf-verify.sh
```

## 9) Backup

```bash
scripts/60-backup-run.sh
```

## 10) Verification Bundle

```bash
kubectl -n openedx-prod get pods
kubectl -n openedx-prod get ingress openedx
kubectl -n openedx-prod get hpa
terraform -chdir=configs/terraform/data-layer output
scripts/53-cloudfront-waf-verify.sh
kubectl -n observability get pods
```

Data-layer connectivity from inside cluster:

```bash
RDS_ENDPOINT=$(terraform -chdir=configs/terraform/data-layer output -raw rds_endpoint)
MONGO_IP=$(terraform -chdir=configs/terraform/data-layer output -raw mongo_private_ip)
REDIS_IP=$(terraform -chdir=configs/terraform/data-layer output -raw redis_private_ip)
ES_IP=$(terraform -chdir=configs/terraform/data-layer output -raw elasticsearch_private_ip)

kubectl -n openedx-prod delete pod verify-net --ignore-not-found
kubectl -n openedx-prod run verify-net --restart=Never --image=busybox:1.36 --command -- sh -c 'sleep 300'
kubectl -n openedx-prod wait --for=condition=Ready pod/verify-net --timeout=120s
kubectl -n openedx-prod exec verify-net -- sh -c "nc -zvw3 ${RDS_ENDPOINT} 3306 && nc -zvw3 ${MONGO_IP} 27017 && nc -zvw3 ${REDIS_IP} 6379 && nc -zvw3 ${ES_IP} 9200"
kubectl -n openedx-prod delete pod verify-net
```

## Cost Control

```bash
scripts/90-cost-pause.sh
scripts/91-cost-resume.sh
```

## Full Cleanup

```bash
scripts/99-destroy-all.sh
```
