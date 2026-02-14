# Troubleshooting Guide

This guide lists the highest-probability failures for this assessment and the fastest commands to diagnose them.

## 1) Cannot Access LMS/CMS in Browser

Symptoms:
- Browser shows 404/502
- CloudFront default domain returns 404
- Login redirects to `apps.lms.openedx.local` and the browser shows DNS error

Checks:
```bash
kubectl -n openedx-prod get pods
kubectl -n openedx-prod get ingress openedx -o wide
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
```

Notes:
- Ingress routes by `Host`. If you curl the NLB hostname without a matching `Host` header, NGINX will return 404.
- The MFE (micro-frontend) login UI uses `apps.lms.openedx.local`. With placeholder domains, you must map it locally (for example in `/etc/hosts`).
- If login/register is stuck on `https://apps.<LMS_HOST>/authn/...`, check that LMS/CMS CORS allow `https://apps.<LMS_HOST>` (see `data-layer/tutor/plugins/openedx-mfe-https.py`).

Test directly against the NLB (replace `NLB_HOSTNAME`):
```bash
NLB_HOSTNAME=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -k -sSI -H 'Host: lms.openedx.local' "https://${NLB_HOSTNAME}/"
curl -k -sSI -H 'Host: studio.openedx.local' "https://${NLB_HOSTNAME}/"
curl -k -sSI -H 'Host: apps.lms.openedx.local' "https://${NLB_HOSTNAME}/authn/login"
```

Verify CORS header is present (required for AuthN MFE):
```bash
curl -kIs -H 'Origin: https://apps.lms.openedx.local' \
  https://lms.openedx.local/api/user/v1/account/registration/ | grep -i access-control-allow-origin
```

CloudFront note:
- `https://<cloudfront>.net/` may return 404 because `Host` does not match the Ingress rules. WAF proof is independent of routing.

## 2) Pods Stuck Pending

Most common causes:
- Not enough nodes or node resources (CPU/memory)
- PVC not bound

Checks:
```bash
kubectl -n openedx-prod get pods -o wide
kubectl -n openedx-prod describe pod <POD_NAME>
kubectl get nodes
kubectl -n openedx-prod get pvc
```

If scale is required:
```bash
eksctl get nodegroup --cluster openedx-eks --region us-east-1
```

## 3) HPA Not Scaling

Requirements:
- metrics-server must be running
- deployments must have CPU requests (HPA needs utilization percentage)

Checks:
```bash
kubectl -n kube-system get deploy metrics-server
kubectl -n openedx-prod get hpa
kubectl -n openedx-prod describe hpa lms-hpa
kubectl -n openedx-prod describe deploy lms | rg -n "Requests:|Limits:" || true
```

Fix (re-apply requests/limits + HPAs):
```bash
infra/k8s/05-hpa/apply.sh
```

If metrics are missing:
```bash
infra/eksctl/install-core-addons.sh
```

## 4) External DB Connectivity Fails From Pods

Symptoms:
- LMS/CMS crashloop
- workers failing to connect to Redis

Fast connectivity probe from inside EKS:
```bash
RDS_ENDPOINT=$(terraform -chdir=infra/terraform output -raw rds_endpoint)
MONGO_IP=$(terraform -chdir=infra/terraform output -raw mongo_private_ip)
REDIS_IP=$(terraform -chdir=infra/terraform output -raw redis_private_ip)
ES_IP=$(terraform -chdir=infra/terraform output -raw elasticsearch_private_ip)

kubectl -n openedx-prod run verify-net --rm -it --image=alpine:3.20 -- sh -c "\
apk add --no-cache busybox-extras curl >/dev/null; \
nc -vz ${RDS_ENDPOINT} 3306; \
nc -vz ${MONGO_IP} 27017; \
nc -vz ${REDIS_IP} 6379; \
nc -vz ${ES_IP} 9200; \
curl -sS http://${ES_IP}:9200/ | head -n 1"
```

If `nc` fails:
- verify SG rules allow inbound from the worker SG
- verify instances are in private subnets in the same VPC as EKS

## 5) Redis Auth Errors (Workers CrashLoop)

Cause:
- password contains special characters and must be URL-encoded
- Tutor may omit auth unless `REDIS_USERNAME` is set

Fix:
- URL-encode the Redis password before saving Tutor config
- set `REDIS_USERNAME=default`

See: `docs/tutor-k8s.md` (Redis URL encoding + username notes).

## 6) Elasticsearch Not Healthy / Connection Refused

Common causes:
- `vm.max_map_count` not set
- heap too large for the instance

Checks on EC2:
```bash
sudo sysctl vm.max_map_count
sudo ls -la /etc/elasticsearch/jvm.options.d/
sudo systemctl status elasticsearch --no-pager
sudo journalctl -u elasticsearch -n 200 --no-pager
```

Expected:
- `vm.max_map_count=262144`
- heap options set (512m-1g range depending on RAM)

## 7) EFS Media Mount Issues (openedx-media)

Symptoms:
- LMS/CMS pods fail to start with mount errors
- `openedx-media` PVC stays Pending

Checks:
```bash
aws eks list-addons --cluster-name openedx-eks --region us-east-1 --output table
kubectl -n kube-system get pods | rg -i "efs|csi" || true
kubectl -n openedx-prod get pvc openedx-media -o wide
kubectl describe pv openedx-media-efs
```

Network requirement:
- NFS 2049/tcp from worker SG to EFS SG must be allowed.

OIDC Terraform error (media-efs):
- Symptom: `expected "url" to have a host, got oidc.eks...`
- Fix: `infra/media-efs/data-sources.tf` must use the full issuer URL (do not strip `https://`).

## 8) Default StorageClass / EBS CSI Missing

Cause:
- EBS CSI driver not installed, or no default StorageClass (for example `gp3` not set as default)

Fix:
```bash
infra/eksctl/install-core-addons.sh
infra/k8s/02-storage/apply.sh
kubectl get storageclass
```

## 9) Grafana Port-Forward Fails (Connection Refused)

Checks:
```bash
kubectl -n observability get pods -l app.kubernetes.io/name=grafana
kubectl -n observability get svc kube-prometheus-stack-grafana -o wide
```

Fix:
- wait for Grafana pod Ready then retry port-forward
- if service port-forward still fails, forward the pod

```bash
POD=$(kubectl -n observability get pods -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
kubectl -n observability port-forward "pod/${POD}" 3000:3000
```

## 10) CloudFront/WAF Proof Not Working

Expected:
- normal request: non-403 (often 404 due to host mismatch)
- blocked request: HTTP/2 403 when `X-Block-Me: 1` is present

Verify:
```bash
infra/cloudfront-waf/verify.sh
```
