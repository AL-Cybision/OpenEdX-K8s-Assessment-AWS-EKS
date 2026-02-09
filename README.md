# AlNafi OpenEdX on AWS EKS — Technical Assessment

This repository contains the infrastructure, configuration, and documentation for deploying Open edX on AWS EKS with external data services, NGINX ingress, observability, and CloudFront + WAF.

## Documentation

- `docs/README.md`
- Reproduction runbook: `docs/reproduce.md`
- Optional: cluster automation: `infra/eksctl/`

## Key Artifacts

- Tutor config (sanitized): `data-layer/tutor/config/config.yml.sanitized`
- ingress-nginx Helm values: `infra/ingress-nginx/values.yaml`
- Media PV/PVC (EFS RWX): `infra/k8s/02-storage/openedx-media-efs.yaml`
- Tutor apply wrapper (Caddy removal + probes + media mount): `infra/k8s/04-tutor-apply/apply.sh`

## Evidence Pack

(Replace the TODO placeholders with links to screenshots saved in `docs/screenshots/`.)

### 1) EKS Cluster Proof
- Screenshot: EKS cluster overview (openedx-eks, Status ACTIVE)
- File: `docs/screenshots/eks-cluster-active.png`
- TODO: Add image link

### 2) OpenEdX Running (Pods + Ingress)
Commands:
```bash
kubectl -n openedx-prod get pods
kubectl -n openedx-prod get ingress openedx
```
Screenshots:
- `docs/screenshots/openedx-pods.png`
- `docs/screenshots/openedx-ingress.png`
- TODO: Add image links

### 3) External Data Layer Proof
Screenshots:
- RDS instance details (endpoint + not public)
  - `docs/screenshots/rds-private-endpoint.png`
- EC2 instances list (mongo/redis/es private IPs, no public IPv4)
  - `docs/screenshots/ec2-private-ips.png`
- TODO: Add image links

Terminal proof (no secrets printed):
```bash
RDS_ENDPOINT=$(./infra/terraform_executable -chdir=infra/terraform output -raw rds_endpoint)
MONGO_IP=$(./infra/terraform_executable -chdir=infra/terraform output -raw mongo_private_ip)
REDIS_IP=$(./infra/terraform_executable -chdir=infra/terraform output -raw redis_private_ip)
ES_IP=$(./infra/terraform_executable -chdir=infra/terraform output -raw elasticsearch_private_ip)

kubectl -n openedx-prod run verify-net --image=alpine:3.20 --restart=Never \
  --command -- sh -c "apk add --no-cache busybox-extras curl >/dev/null; \
  getent hosts ${RDS_ENDPOINT} || true; \
  nc -vz ${RDS_ENDPOINT} 3306; \
  nc -vz ${MONGO_IP} 27017; \
  nc -vz ${REDIS_IP} 6379; \
  nc -vz ${ES_IP} 9200; \
  curl -sS http://${ES_IP}:9200/ | head -n 50"

kubectl -n openedx-prod logs verify-net
kubectl -n openedx-prod delete pod verify-net --ignore-not-found
```

### 4) HPA Scaling Proof
Generate load (k6):
```bash
kubectl -n openedx-prod create configmap k6-script \
  --from-file=loadtest-k6.js=infra/k8s/05-hpa/loadtest-k6.js \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n openedx-prod delete job k6-loadtest --ignore-not-found

cat <<'YAML' | kubectl apply -f -
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

Command:
```bash
kubectl -n openedx-prod get hpa
```
Screenshot:
- `docs/screenshots/hpa-scaling.png`
- TODO: Add image link

Optional:
```bash
kubectl -n openedx-prod get deploy lms -w
```
- `docs/screenshots/hpa-scale-watch.png`

### 5) Grafana Dashboard
Commands (do not screenshot password output):
```bash
kubectl -n observability get secret kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d ; echo

kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Screenshot:
- `docs/screenshots/grafana-dashboard.png`
- TODO: Add image link

### 6) Central Logs (Loki)
Grafana Explore:
- Datasource: `Loki`
- Query: `{namespace="openedx-prod", pod=~"lms-.*"}`
- If Explore shows `React Monaco Editor failed to load`, switch from `Code` to `Builder`.

Screenshot:
- `docs/screenshots/loki-logs.png`
- TODO: Add image link

### 7) CloudFront + WAF
Screenshots:
- CloudFront distribution details: `docs/screenshots/cloudfront-details.png`
- WAF WebACL + rule: `docs/screenshots/waf-webacl.png`
- TODO: Add image links

Terminal proof of block:
```bash
CF_DOMAIN=$(./infra/terraform_executable -chdir=infra/cloudfront-waf output -raw cloudfront_domain_name)

curl -sSI -H "X-Block-Me: 1" "https://${CF_DOMAIN}/"
```
Screenshot:
- `docs/screenshots/waf-block-403.png`
- TODO: Add image link

---

For the full ordered checklist, see `docs/evidence-checklist.md`.
