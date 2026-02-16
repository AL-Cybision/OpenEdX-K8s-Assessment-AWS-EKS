# Repo Walkthrough

This file explains what each directory is for, what is actively used, and what is optional.

## Root

- `README.md`: main submission entrypoint for reviewers.
- `AGENTS.md`: operating guide for humans/agents.
- `docs/`: runbooks, architecture, evidence, troubleshooting.
- `infra/`: automation scripts and Terraform for AWS/K8s platform.
- `k8s/`: Kubernetes manifests (namespaces + ingress resources).
- `data-layer/`: Tutor config/plugins and external DB bootstrap artifacts.

## `infra/` (active execution paths)

- `infra/eksctl/`: EKS lifecycle and mandatory core add-ons automation.
  - `create-cluster.sh`, `harden-endpoint.sh`, `delete-cluster.sh`, `install-core-addons.sh`
- `infra/terraform/`: external data layer (RDS + EC2 Mongo/Redis/Elasticsearch).
  - `apply.sh`, `destroy.sh`, `*.tf`
- `infra/media-efs/`: EFS for shared media/upload persistence.
  - `apply.sh`, `*.tf`
- `infra/k8s/04-tutor-apply/`: Tutor apply wrapper; removes edge Caddy and patches runtime.
  - `apply.sh`, `postrender-remove-caddy.py`
- `infra/k8s/05-hpa/`: HPA + k6 load test assets.
- `infra/ingress-nginx/`: ingress-nginx install/uninstall + values.
- `infra/cert-manager/`: production TLS path (Let’s Encrypt).
- `infra/observability/`: kube-prometheus-stack + loki-stack installation and alerts.
- `infra/cloudfront-waf/`: CloudFront + WAF deploy/verify.
- `infra/cost/`: pause/resume scripts for cost control.
- `infra/backups/`: backup and restore scripts.
- `infra/ses/`: optional SES SMTP setup for activation emails.

## `k8s/`

- `k8s/00-namespaces/namespaces.yaml`: required namespaces.
- `k8s/03-ingress/real-domain/apply.sh`: production ingress + TLS on real domain.
- `k8s/02-storage/storageclass-gp3.yaml`: default storage class baseline.

## `data-layer/`

- `data-layer/tutor/config/config.yml.sanitized`: sanitized Tutor config reference.
- `data-layer/tutor/plugins/openedx-mfe-https.py`: MFE HTTPS/CORS/runtime fix plugin.
- `data-layer/tutor/plugins/openedx-elasticsearch.py`: Elasticsearch backend plugin (Meilisearch off).
- `data-layer/user-data/*.sh`: EC2 bootstrap scripts for mongo/redis/elasticsearch.
- `data-layer/scripts/*`: DB connectivity/init helpers.

## `docs/` (what to read first)

- `docs/reproduce.md`: step-by-step runbook (source of truth).
- `docs/operator-quickstart.md`: minimal deploy/verify/pause/resume flow.
- `docs/evidence-checklist.md`: screenshot and terminal proof checklist.
- `docs/config-artifacts.md`: where each required artifact lives.
- `docs/troubleshooting.md`: known failure modes and fixes.

See `docs/repo-cleanup.md` for removed legacy artifacts.
