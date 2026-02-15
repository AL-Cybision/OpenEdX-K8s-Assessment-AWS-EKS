# AlNafi Open edX on AWS EKS (Assessment) - Agent Guide

This file is the operating manual for anyone (human or agent) working in this repository.
Goal: make the deployment reproducible, verifiable, and cost-controlled without tribal knowledge.

## What

Deploy a production-style Open edX platform on **AWS EKS (us-east-1)** using **Tutor + tutor-k8s** with:
- **NGINX Ingress** (replacing Tutor's default Caddy at the edge)
- **External data layer** (NOT in Kubernetes):
  - MySQL on **AWS RDS**
  - MongoDB on **EC2**
  - Redis on **EC2**
  - Elasticsearch on **EC2**
- PV/PVC for media, HPA for LMS/CMS, observability (Prometheus/Grafana + Loki), CloudFront + WAF, backups
- Evidence pack (screenshots + terminal proof) committed under `docs/screenshots/`

## Why

This repo is the submission for the "OpenEdX on Kubernetes (AWS EKS) - Technical Assessment".
The scoring is driven by:
- correctness of architecture (EKS + external data services + ingress + CDN/WAF)
- proof of implementation (screenshots + command outputs)
- reproducibility (assessor can follow `docs/reproduce.md` and succeed)

## Where (Repo Map)

Primary entry points:
- `README.md`: submission overview + evidence images (what reviewers will read first)
- `docs/reproduce.md`: assessor-friendly step-by-step runbook (script-driven)
- `docs/config-artifacts.md`: index of configuration artifacts (YAML/TF/scripts)

Infrastructure:
- `infra/eksctl/`: create/delete cluster and core add-ons automation
- `infra/terraform/`: external data layer (RDS + EC2 Mongo/Redis/Elasticsearch) via Terraform
- `infra/ingress-nginx/`: NGINX ingress controller install (Helm) + values
- `infra/observability/`: kube-prometheus-stack + loki-stack install + alerts
- `infra/cloudfront-waf/`: CloudFront + WAF Terraform + apply/verify scripts
- `infra/k8s/`: Kubernetes automation (storage, tutor apply wrapper, HPA, etc)
- `infra/ses/`: optional "professional" SMTP relay via Amazon SES (activation emails)

Application layer:
- `data-layer/tutor/config/config.yml.sanitized`: sanitized Tutor config used for reference
- `data-layer/tutor/plugins/`: Tutor plugins used in this deployment (for example HTTPS fixes for MFEs)

Kubernetes manifests:
- `k8s/`: namespace + ingress-related YAML and helper scripts

Evidence:
- `docs/evidence-checklist.md`: ordered checklist of required screenshots/commands
- `docs/screenshots/`: committed screenshot evidence

## How (Reproduction)

Follow `docs/reproduce.md`. It is the source of truth for exact commands.

High-level execution order:
1. (Optional) Create EKS cluster: `infra/eksctl/create-cluster.sh`
2. Core add-ons: `infra/eksctl/install-core-addons.sh` (EBS CSI, gp3 default, metrics-server)
3. Namespaces: `kubectl apply -f k8s/00-namespaces/namespaces.yaml`
4. NGINX ingress: `infra/ingress-nginx/install.sh`
5. External data layer: `infra/terraform/apply.sh`
6. Storage: `infra/media-efs/apply.sh` then `infra/k8s/02-storage/apply.sh`
7. Tutor/Open edX: `infra/k8s/04-tutor-apply/apply.sh` (post-render removes Caddy, adds probes/mounts)
8. Ingress rules: `k8s/03-ingress/create-selfsigned-tls.sh` then `kubectl apply -f k8s/03-ingress/openedx-ingress.yaml`
9. HPA + load test: `infra/k8s/05-hpa/apply.sh` then follow `docs/hpa-loadtest.md`
10. Observability: `infra/observability/install.sh`
11. CloudFront + WAF: `infra/cloudfront-waf/apply.sh` and `infra/cloudfront-waf/verify.sh`
12. Backups: `infra/backups/backup.sh` (see `docs/backup-restore.md`)

## How (Verification)

Kubernetes health:
- `kubectl -n openedx-prod get pods`
- `kubectl -n openedx-prod get ingress openedx`
- `kubectl -n openedx-prod get hpa`

Data-layer reachability (from inside the cluster):
- Use the `verify-net` pod pattern in `docs/reproduce.md` (no secrets printed)

Ingress/LB access (placeholder domains):
- `lms.openedx.local`, `studio.openedx.local`, `apps.lms.openedx.local`
- These require `/etc/hosts` mapping to the ingress load balancer IP. See `docs/reproduce.md`.

## SES Email Activation (Optional, Production-Style)

If learner activation is enabled, SMTP must work or learners cannot complete signup.

This repo keeps the architecture unchanged:
- Open edX sends email to in-cluster `smtp:8025`
- The `smtp` pod (Exim relay) relays outbound via **Amazon SES SMTP** on port `587` with auth

Important constraints:
- SES sandbox (`ProductionAccessEnabled=false`) only delivers to verified identities.
- The sender identity must match Open edX's actual from-address. Default is typically `contact@<LMS_HOST>`.

Runbook section: `docs/reproduce.md` -> "Email Activation (Professional SMTP via Amazon SES)".

## When (Cost Control)

Overnight pause (keeps resources, reduces most variable cost):
- Scale EKS nodegroup to `desired=0`
- Stop EC2 data-layer instances (mongo/redis/elasticsearch)

Resume:
- Scale nodegroup back to `desired>=2` (use `3` if pods are Pending due to CPU/memory)
- Start EC2 data-layer instances

Notes:
- EKS control plane still bills even with 0 nodes.
- RDS bills while running.
- NAT Gateway (if created by eksctl VPC) bills continuously; true "max savings" requires deleting the cluster/VPC stack.

## Hard Requirements (Do Not Violate)

- AWS region: `us-east-1`
- Kubernetes platform: **AWS EKS only**
- Databases must be external to Kubernetes (no DB containers in-cluster)
- Data-layer must not be publicly accessible; only worker security group may reach DB ports
- Keep costs low (smallest reasonable instance types)
- Never commit secrets or Terraform state to git; never paste secrets into logs/docs

## Common Failure Modes (Fast Triage)

- Pods Pending after resume: node capacity too small.
  - Scale nodegroup to `desired=3` temporarily.
- HPA shows `cpu: <unknown>`: metrics-server missing/unhealthy.
  - Fix via `infra/eksctl/install-core-addons.sh`, then `kubectl top nodes`.
- Meilisearch PVC stuck: EBS CSI or default `gp3` StorageClass missing.
  - Ensure EBS CSI add-on + `gp3` default, then recreate PVC.
- MFE white screen / auth redirect loops with `.local` domains:
  - Use consistent HTTPS hostnames and the HTTPS MFE plugin documented in `docs/reproduce.md`.
  - Real DNS + trusted certs (Route53/ACM or cert-manager) is the production fix; `.local` is assessment-mode.
- SES mail rejected:
  - Verify SES identities (domain + DKIM) and sandbox/production access status.

