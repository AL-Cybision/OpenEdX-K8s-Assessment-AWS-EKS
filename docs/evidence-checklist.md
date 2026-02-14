# Evidence Checklist (Screenshots + Terminal Proof)

Use this exact order to match the rubric.

## 1) EKS Cluster Proof (AWS Console)
- Screenshot: EKS cluster overview page for `openedx-eks` (Status: **ACTIVE**)
- File: `docs/screenshots/eks-cluster-active.png`

## 2) OpenEdX Running (Terminal)
### Command
```bash
kubectl -n openedx-prod get pods
```
- Screenshot: output showing `lms`, `cms`, `lms-worker`, `cms-worker`, `mfe`, `smtp` **Running**
- File: `docs/screenshots/openedx-pods.png`

### Command
```bash
kubectl -n openedx-prod get ingress openedx
```
- Screenshot: output showing hosts `lms.openedx.local` and `studio.openedx.local`
- File: `docs/screenshots/openedx-ingress.png`

### Command
```bash
kubectl -n openedx-prod get svc mfe -o wide
```
- Screenshot: output showing `mfe` service type is `ClusterIP`
- File: `docs/screenshots/mfe-service-clusterip.png`

### Screenshot (Browser)
- Screenshot: LMS UI page loads in browser (Welcome to My Open edX)
- File: `docs/screenshots/OpenEdxLMS.png`

## 3) External Data Layer Proof (AWS Console)
- Screenshot: RDS instance details page showing endpoint and private networking (e.g., Internet access gateway: Disabled / not public)
  - File: `docs/screenshots/rds-private-endpoint.png`
- Screenshot: EC2 instances list for mongo/redis/es showing **Private IPs** and **No public IPv4**
  - File: `docs/screenshots/ec2-private-ips.png`

### Terminal proof (from inside EKS, no secrets printed)
```bash
RDS_ENDPOINT=$(terraform -chdir=infra/terraform output -raw rds_endpoint)
MONGO_IP=$(terraform -chdir=infra/terraform output -raw mongo_private_ip)
REDIS_IP=$(terraform -chdir=infra/terraform output -raw redis_private_ip)
ES_IP=$(terraform -chdir=infra/terraform output -raw elasticsearch_private_ip)

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

## 3.1) Studio Course + Mongo Persistence + Pod Restart (Terminal + UI)
### Create Course in Studio
- Open `https://studio.openedx.local`
- Create a new course (for example `compliance-101`) and publish at least one unit/page
- Screenshot: course exists in Studio
- File: `docs/screenshots/studio-course-created.png`

### Verify Mongo collections for course/modulestore
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
- Screenshot: `mongo-verify` logs show course/modulestore-related collections
- File: `docs/screenshots/mongo-course-persistence.png`

### Restart application pods and re-verify course
```bash
kubectl -n openedx-prod rollout restart deploy/lms deploy/cms
kubectl -n openedx-prod rollout status deploy/lms --timeout=10m
kubectl -n openedx-prod rollout status deploy/cms --timeout=10m
```
- Screenshot: same course still visible after restart
- File: `docs/screenshots/course-persistence-after-restart.png`

## 4) HPA Scaling Proof (Terminal)
### Generate Load (k6) + Watch HPA
Pre-step:
```bash
infra/k8s/05-hpa/apply.sh
kubectl top nodes
```

Run load (in-cluster) in one terminal:
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

Watch scaling in another terminal:
```bash
kubectl -n openedx-prod get hpa -w
```

### Screenshot Command
```bash
kubectl -n openedx-prod get hpa
```
- Screenshot: LMS shows **6 replicas** and high CPU utilization
- File: `docs/screenshots/hpa-scaling.png`

Optional (if you want a live scale log):
```bash
kubectl -n openedx-prod get deploy lms -w
```
This is optional evidence only and is not required for the minimum checklist.

## 5) Grafana Dashboard (UI)
### Commands (do not screenshot password output)
```bash
kubectl -n observability get secret kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d ; echo

kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

- Screenshot: Grafana dashboard with CPU/memory/time series for `openedx-prod`
- Dashboard: `Kubernetes / Compute Resources / Namespace (Pods)` with `namespace=openedx-prod`
- File: `docs/screenshots/grafana-dashboard.png`

## 6) Central Logs (UI)
- Screenshot: Grafana Explore (Loki) showing a LogQL graph derived from `lms` logs (top paths)
- Datasource: `Loki`
- Query (graph, from `lms` logs): `topk(5, sum by (path) (rate({namespace="openedx-prod", pod=~"lms-.*"} | regexp "GET (?P<path>/[^ ]*)"[5m])))`
- Raw logs query (optional): `{namespace="openedx-prod", pod=~"lms-.*"}`
- If Explore shows `React Monaco Editor failed to load`, switch from `Code` to `Builder`.
- File: `docs/screenshots/loki-logs.png`

## 7) CloudFront + WAF (AWS Console + Terminal)
- Screenshot: CloudFront distribution details (domain visible)
  - File: `docs/screenshots/cloudfront-details.png`
- Screenshot: WAF WebACL + rule page
  - File: `docs/screenshots/waf-webacl.png`

### Command (Terminal proof of block)
```bash
CF_DOMAIN=$(terraform -chdir=infra/cloudfront-waf output -raw cloudfront_domain_name)

curl -sSI -H "X-Block-Me: 1" "https://${CF_DOMAIN}/"
```
- Screenshot: output showing **HTTP/2 403**
- File: `docs/screenshots/waf-block-403.png`
