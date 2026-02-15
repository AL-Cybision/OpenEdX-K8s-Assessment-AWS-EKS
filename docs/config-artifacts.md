# Configuration Artifacts Index

This page maps the assessment's "Configuration Artifacts" checklist to the exact files in this repository.

Goal: reviewers can find artifacts quickly without hunting through folders.

## 1) Kubernetes Manifests (YAML)

Namespaces:
- `k8s/00-namespaces/namespaces.yaml`

Ingress resources:
- `k8s/03-ingress/real-domain/apply.sh` (production-mode: real domain + Let’s Encrypt TLS via cert-manager)
- `k8s/03-ingress/openedx-ingress.yaml` (assessment-mode fallback: placeholder hosts + self-signed TLS + routing, rate-limits)
- `k8s/01-echo-ingress.yaml` (sanity test ingress used early)

Storage:
- `k8s/02-storage/storageclass-gp3.yaml` (EBS gp3 StorageClass)
- `infra/k8s/02-storage/openedx-media-efs.yaml` (EFS-backed PV+PVC for shared media/uploads)

HPA:
- `infra/k8s/05-hpa/lms-hpa.yaml`
- `infra/k8s/05-hpa/cms-hpa.yaml`

Tutor/Open edX:
- Tutor generates Open edX manifests under `~/.local/share/tutor/env/` (not committed because it contains environment-specific values).
- Apply path is deterministic via: `infra/k8s/04-tutor-apply/apply.sh` (post-render patch removes Caddy and injects probes + media mounts).

## 2) Tutor Configuration Files

Sanitized Tutor config artifact (no secrets):
- `data-layer/tutor/config/config.yml.sanitized`

Config export script (redacts secrets):
- `data-layer/tutor/scripts/export-sanitized-config.py`

Tutor plugins:
- `data-layer/tutor/plugins/` (local plugins: Elasticsearch backend + HTTPS MFE CORS fix)

Tutor deployment wrapper (always use this to avoid Caddy reappearing):
- `infra/k8s/04-tutor-apply/apply.sh`
- `infra/k8s/04-tutor-apply/postrender-remove-caddy.py`

## 3) NGINX Configuration Files

Ingress controller (Helm values used in this deployment):
- `infra/ingress-nginx/values.yaml`

Ingress controller install script (pinned chart version):
- `infra/ingress-nginx/install.sh`

Ingress routing configuration (NGINX ingress annotations + hosts + TLS):
- Production-mode: `k8s/03-ingress/real-domain/apply.sh`
- Assessment-mode fallback: `k8s/03-ingress/openedx-ingress.yaml`

## 4) Helm Charts (If Used)

This repo uses upstream Helm charts and pins configuration via values files and install scripts (charts are not vendored).

ingress-nginx:
- `infra/ingress-nginx/install.sh`
- `infra/ingress-nginx/values.yaml`

Observability (Prometheus/Grafana + Loki):
- `infra/observability/install.sh`
- `infra/observability/values-kube-prometheus-stack.yaml`
- `infra/observability/values-loki-stack.yaml`

cert-manager (production-mode TLS for real domains via Let’s Encrypt):
- `infra/cert-manager/install.sh`

## 5) Database Connection + Initialization Scripts

DB provisioning (Terraform):
- `infra/terraform/` (RDS + EC2 data nodes + SG restrictions + optional S3 gateway endpoint)
- Script entrypoint: `infra/terraform/apply.sh`

EC2 bootstrap (user-data):
- `data-layer/user-data/mongo.sh` (MongoDB install + auth + bind)
- `data-layer/user-data/redis.sh` (Redis install + auth)
- `data-layer/user-data/elasticsearch.sh` (ES install + heap + vm.max_map_count)

Init/test scripts:
- `data-layer/scripts/mysql-init.sql`
- `data-layer/scripts/mongo-init.js`
- `data-layer/scripts/redis-test.sh`
- `data-layer/scripts/es-test.sh`

## 6) Ingress Controller + Ingress Resources

Controller:
- `infra/ingress-nginx/install.sh`
- `infra/ingress-nginx/values.yaml`

Ingress resources:
- `k8s/03-ingress/openedx-ingress.yaml`
- `k8s/01-echo-ingress.yaml`

## Related Deliverables (Docs)

Reproduction runbook:
- `docs/reproduce.md`

Evidence checklist (screenshots + terminal proof):
- `docs/evidence-checklist.md`

## Automation (Scripts)

Deployment automation entrypoints:
- `docs/reproduce.md` (end-to-end runbook)
- `infra/eksctl/install-core-addons.sh` (EBS CSI + gp3 default + metrics-server)
- `infra/cert-manager/install.sh` (production-mode TLS: cert-manager + Let’s Encrypt)
- `infra/terraform/apply.sh` (external data layer)
- `infra/media-efs/apply.sh` (EFS media layer)
- `infra/k8s/04-tutor-apply/apply.sh` (Tutor apply wrapper)
- `infra/ses/setup.sh` (optional: SES identities + Secrets Manager SMTP creds)
- `infra/ses/apply.sh` (optional: configure smtp relay to use SES)
- `infra/cloudfront-waf/apply.sh` (CloudFront + WAF)
- `infra/observability/install.sh` (monitoring stack)

Backup and restore:
- `infra/backups/backup.sh`
- `infra/backups/restore.sh`

Monitoring and alerting configuration:
- `infra/observability/values-kube-prometheus-stack.yaml` (Prometheus/Grafana + Alertmanager)
- `infra/observability/values-loki-stack.yaml` (Loki/Promtail)
- `infra/observability/openedx-prometheusrule.yaml` (custom alerts)
