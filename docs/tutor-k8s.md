# Tutor + Open edX on EKS (External Data Layer)

This document captures the **current deployment steps and fixes** for running Open edX (Tutor v21) on the `openedx-eks` cluster using **external MySQL/MongoDB/Redis** and NGINX ingress (Caddy removed).

## Environment

- Cluster: `openedx-eks` (us-east-1)
- Namespace: `openedx-prod`
- Tutor: `v21.0.1` (installed in project venv)
- Open edX image: `docker.io/overhangio/openedx:21.0.1-indigo`
- MFE image: `docker.io/overhangio/openedx-mfe:21.0.0-indigo` (latest tag available in this environment)

Config artifacts (checked into this repo):
- Sanitized Tutor config: `data-layer/tutor/config/config.yml.sanitized`
- ingress-nginx Helm values: `infra/ingress-nginx/values.yaml`

## Install Tutor and Plugins

```bash
python3 -m venv .venv
.venv/bin/python3 -m pip install --upgrade pip
.venv/bin/python3 -m pip install "tutor==21.0.1"
.venv/bin/tutor plugins install mfe
.venv/bin/tutor plugins install indigo
```

## Configure Tutor for External Databases

Use AWS Secrets Manager for the DB credentials. **Do not print secrets.**

```bash
RDS_SECRET_ARN=$(terraform -chdir=infra/terraform output -raw rds_secret_arn)
MONGO_SECRET_ARN=$(terraform -chdir=infra/terraform output -raw mongo_secret_arn)
REDIS_SECRET_ARN=$(terraform -chdir=infra/terraform output -raw redis_secret_arn)

MONGO_IP=$(terraform -chdir=infra/terraform output -raw mongo_private_ip)
REDIS_IP=$(terraform -chdir=infra/terraform output -raw redis_private_ip)
ES_IP=$(terraform -chdir=infra/terraform output -raw elasticsearch_private_ip)

RDS_SECRET=$(aws secretsmanager get-secret-value --secret-id "$RDS_SECRET_ARN" --region us-east-1 --query SecretString --output text)
MONGO_SECRET=$(aws secretsmanager get-secret-value --secret-id "$MONGO_SECRET_ARN" --region us-east-1 --query SecretString --output text)
REDIS_SECRET=$(aws secretsmanager get-secret-value --secret-id "$REDIS_SECRET_ARN" --region us-east-1 --query SecretString --output text)

RDS_USER=$(echo "$RDS_SECRET" | jq -r '.username')
RDS_PASS=$(echo "$RDS_SECRET" | jq -r '.password')
RDS_HOST=$(echo "$RDS_SECRET" | jq -r '.host')
RDS_PORT=$(echo "$RDS_SECRET" | jq -r '.port')
RDS_DB=$(echo "$RDS_SECRET" | jq -r '.dbname')

MONGO_USER=$(echo "$MONGO_SECRET" | jq -r '.app_username')
MONGO_PASS=$(echo "$MONGO_SECRET" | jq -r '.app_password')
MONGO_DB=$(echo "$MONGO_SECRET" | jq -r '.dbname')

REDIS_PASS_RAW=$(echo "$REDIS_SECRET" | jq -r '.password')
export REDIS_PASS_RAW
REDIS_PASS_URL=$(python3 - <<'PY'
import os, urllib.parse
print(urllib.parse.quote(os.environ['REDIS_PASS_RAW'], safe=''))
PY
)

.venv/bin/tutor config save \
  -s LMS_HOST=lms.openedx.local \
  -s CMS_HOST=studio.openedx.local \
  -s K8S_NAMESPACE=openedx-prod \
  -s ENABLE_WEB_PROXY=false \
  -s RUN_MYSQL=false \
  -s RUN_MONGODB=false \
  -s RUN_REDIS=false \
  -s RUN_MEILISEARCH=false \
  -s OPENEDX_IMAGE="docker.io/overhangio/openedx:21.0.1-indigo" \
  -s MFE_DOCKER_IMAGE="docker.io/overhangio/openedx-mfe:21.0.0-indigo" \
  -s ELASTICSEARCH_HOST="http://${ES_IP}:9200" \
  -s MYSQL_HOST="$RDS_HOST" \
  -s MYSQL_PORT="$RDS_PORT" \
  -s MYSQL_ROOT_USERNAME="$RDS_USER" \
  -s MYSQL_ROOT_PASSWORD="$RDS_PASS" \
  -s OPENEDX_MYSQL_USERNAME="$RDS_USER" \
  -s OPENEDX_MYSQL_PASSWORD="$RDS_PASS" \
  -s OPENEDX_MYSQL_DATABASE="$RDS_DB" \
  -s MONGODB_HOST="$MONGO_IP" \
  -s MONGODB_PORT=27017 \
  -s MONGODB_USERNAME="$MONGO_USER" \
  -s MONGODB_PASSWORD="$MONGO_PASS" \
  -s MONGODB_DATABASE="$MONGO_DB" \
  -s MONGODB_AUTH_SOURCE="$MONGO_DB" \
  -s REDIS_HOST="$REDIS_IP" \
  -s REDIS_PORT=6379 \
  -s REDIS_USERNAME="default" \
  -s REDIS_PASSWORD="$REDIS_PASS_URL"
```

Notes:
- Redis password is **URL-encoded** to keep Celery broker URLs valid.
- Set `REDIS_USERNAME=default` so Tutor includes credentials in rendered `redis://` URLs (Redis ACL default user + `requirepass`).

## Storage Baseline (EBS CSI + Default StorageClass)

This deployment sets `gp3` as the default StorageClass (EBS CSI), as a baseline for EKS dynamic PV provisioning.

```bash
kubectl get storageclass
kubectl get storageclass gp2 >/dev/null 2>&1 && \
  kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass gp3 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Shared Media Storage (Uploads/Media PVC)

Open edX uploads/media must be shared across LMS/CMS replicas. EBS gp3 volumes are `ReadWriteOnce`, so this deployment uses EFS (`ReadWriteMany`) for the `openedx-media` PVC.

Provision EFS + EFS CSI driver:
```bash
infra/media-efs/apply.sh
```

Create the EFS-backed PV/PVC:
```bash
infra/k8s/02-storage/apply.sh
```

The PVC is mounted into `lms` and `cms` at `/openedx/media` by the post-render filter:
- `infra/k8s/04-tutor-apply/postrender-remove-caddy.py`

Verify:
```bash
kubectl -n openedx-prod get pvc openedx-media
kubectl -n openedx-prod describe deploy lms | rg openedx-media
kubectl -n openedx-prod describe deploy cms | rg openedx-media
```

## Deploy and Initialize

```bash
infra/k8s/04-tutor-apply/apply.sh
.venv/bin/tutor k8s init
```

## Fix MFE Login/Register Under HTTPS (Required)

Because TLS terminates at the NGINX Ingress, MFEs are served over **HTTPS**.
Tutor defaults add only `http://apps.<LMS_HOST>` to CORS/CSRF allow-lists, which
breaks the AuthN MFE in the browser (register/login gets stuck).

Enable a small local Tutor plugin that adds the `https://apps.<LMS_HOST>` origin
to the LMS/CMS CORS + CSRF trusted origins, then re-apply:

```bash
mkdir -p "${HOME}/.local/share/tutor-plugins"
cp data-layer/tutor/plugins/openedx-mfe-https.py "${HOME}/.local/share/tutor-plugins/openedx-mfe-https.py"
.venv/bin/tutor plugins enable openedx-mfe-https

infra/k8s/04-tutor-apply/apply.sh
```

Verification:

```bash
curl -kIs -H 'Origin: https://apps.lms.openedx.local' \
  https://lms.openedx.local/api/user/v1/account/registration/ | rg -i 'access-control-allow-origin'
```

## Enable Elasticsearch Backend (Search)

Tutor v21 includes an optional Meilisearch service by default. For strict compliance with
"no databases in Kubernetes", this deployment disables Meilisearch (`RUN_MEILISEARCH=false`)
and uses **external Elasticsearch on EC2** as the search backend.

Plugin file (source of truth):
- `data-layer/tutor/plugins/openedx-elasticsearch.py`

Install/enable the local plugin and re-apply (note: `infra/k8s/04-tutor-apply/apply.sh`
also copies/enables this plugin to avoid stale local plugin copies):

```bash
mkdir -p "${HOME}/.local/share/tutor-plugins"
cp data-layer/tutor/plugins/openedx-elasticsearch.py "${HOME}/.local/share/tutor-plugins/openedx-elasticsearch.py"
.venv/bin/tutor plugins enable openedx-elasticsearch
.venv/bin/tutor k8s start
```

Proof config from inside LMS:

```bash
kubectl -n openedx-prod exec -i deploy/lms -- python - <<'PY'
import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "lms.envs.tutor.production")
import django
django.setup()
from django.conf import settings
print(settings.SEARCH_ENGINE)
print(settings.ELASTIC_SEARCH_CONFIG)
print(settings.ELASTIC_SEARCH_INDEX_PREFIX)
print(settings.MEILISEARCH_ENABLED)
PY
```

Captured output:

```text
SEARCH_ENGINE= search.elastic.ElasticSearchEngine
ELASTIC_SEARCH_CONFIG= [{'hosts': ['http://192.168.95.171:9200']}]
ELASTIC_SEARCH_INDEX_PREFIX= tutor_
MEILISEARCH_ENABLED= False
```

Simple index/query verification from inside LMS:

```bash
ES_IP=$(terraform -chdir=infra/terraform output -raw elasticsearch_private_ip)
kubectl -n openedx-prod exec -i deploy/lms -- sh -c '
curl -s -X POST "http://'"${ES_IP}"':9200/tutor_verify/_doc/1?refresh=wait_for" \
  -H "Content-Type: application/json" \
  -d "{\"title\":\"openedx-es\"}" >/tmp/es_post.json
curl -s "http://'"${ES_IP}"':9200/tutor_verify/_search?q=title:openedx-es" >/tmp/es_search.json
cat /tmp/es_post.json
echo
cat /tmp/es_search.json
'
```

Captured result:

```text
{"_index":"tutor_verify","_type":"_doc","_id":"1","_version":2,"result":"updated","_shards":{"total":2,"successful":1,"failed":0},"_seq_no":1,"_primary_term":1}
{"took":8,"timed_out":false,"_shards":{"total":1,"successful":1,"skipped":0,"failed":0},"hits":{"total":{"value":1,"relation":"eq"},"max_score":0.36464313,"hits":[{"_index":"tutor_verify","_type":"_doc","_id":"1","_score":0.36464313,"_source":{"title":"openedx-es"}}]}}
```

## NGINX Ingress (Replace Caddy)

Apply ingress and create a TLS secret (self-signed for placeholder domains):

```bash
k8s/03-ingress/create-selfsigned-tls.sh
kubectl apply -f k8s/03-ingress/openedx-ingress.yaml
```

## Permanent Caddy Removal (Post-render)

Tutor generates Caddy resources by default. The wrapper script uses a post-render filter to remove Caddy resources and Job/Namespace objects before apply.
The same filter also normalizes `mfe` service type to `ClusterIP` (internal-only).

- Wrapper: `infra/k8s/04-tutor-apply/apply.sh`
- Filter: `infra/k8s/04-tutor-apply/postrender-remove-caddy.py`

Use the wrapper every time you apply Tutor manifests:

```bash
infra/k8s/04-tutor-apply/apply.sh
```

## Health Probes (Liveness/Readiness)

Liveness and readiness probes are injected by the post-render filter:
- `infra/k8s/04-tutor-apply/postrender-remove-caddy.py`

Probes added:
- LMS/CMS: HTTP `/heartbeat` on port 8000
- MFE: HTTP `/` on port 8002
- SMTP: TCP 8025
- Workers: `exec` check for celery process
## Verification

```bash
kubectl -n openedx-prod get pods
kubectl -n openedx-prod get ingress openedx
kubectl -n openedx-prod get svc mfe -o wide
```

Expected: `lms`, `cms`, `lms-worker`, `cms-worker`, `mfe`, `smtp` all Running and `mfe` service type is `ClusterIP`.

## Known Constraints

- Use `infra/k8s/04-tutor-apply/apply.sh` so Caddy is removed via post-render filtering.
