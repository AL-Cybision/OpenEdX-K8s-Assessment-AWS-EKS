# Operator Quickstart

Use this when you want the shortest operational path.

Assumptions:
- AWS credentials are configured
- Region is `us-east-1`
- You are in repo root

## 1) Deploy

```bash
# 1) Cluster (optional if cluster already exists)
infra/eksctl/create-cluster.sh

# 1b) Harden EKS API endpoint (recommended on existing clusters too)
infra/eksctl/harden-endpoint.sh

# 2) Core add-ons (mandatory)
infra/eksctl/install-core-addons.sh

# 3) Namespaces + ingress controller
kubectl apply -f k8s/00-namespaces/namespaces.yaml
infra/ingress-nginx/install.sh

# 4) External data + shared media
infra/terraform/apply.sh
infra/media-efs/apply.sh
infra/k8s/02-storage/apply.sh

# 5) Open edX + ingress/TLS
infra/k8s/04-tutor-apply/apply.sh
infra/cert-manager/install.sh
# then apply real-domain ingress (set vars first)
k8s/03-ingress/real-domain/apply.sh

# 6) Scale/obs/security
infra/k8s/05-hpa/apply.sh
infra/observability/install.sh
infra/cloudfront-waf/apply.sh

# Optional CloudFront hardening (only with trusted cert on origin domain)
# ORIGIN_DOMAIN_NAME=lms.example.com ORIGIN_PROTOCOL_POLICY=https-only infra/cloudfront-waf/apply.sh
```

## 2) Verify

```bash
kubectl -n openedx-prod get pods
kubectl -n openedx-prod get ingress openedx
kubectl -n openedx-prod get hpa
infra/cloudfront-waf/verify.sh
```

For full verification and evidence commands, use `docs/reproduce.md` and `docs/evidence-checklist.md`.

## 3) Pause (Cost Save)

```bash
infra/cost/pause.sh
```

## 4) Resume

```bash
infra/cost/resume.sh
```

If pods stay `Pending` after resume, temporarily increase nodegroup desired size to 3.
