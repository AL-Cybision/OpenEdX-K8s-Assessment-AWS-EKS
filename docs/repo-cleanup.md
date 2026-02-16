# Repo Cleanup Notes

This list identifies files that were either removed or intentionally kept.

## Removed (to reduce confusion)

- `k8s/03-ingress/disable-caddy.sh`
  - Removed because Caddy removal is already enforced permanently in `infra/k8s/04-tutor-apply/postrender-remove-caddy.py`.
- `k8s/02-storage/pvc-openedx-media.yaml`
  - Removed old EBS RWO lab PVC to avoid conflict with the production EFS RWX media path.
- `k8s/02-storage/pod-pvc-test.yaml`
  - Removed one-off PVC test pod (not part of production runbook).
- `data-layer/tutor/plugins/openedx-elasticsearch/` (legacy plugin folder)
  - Removed unused duplicate plugin implementation. Active plugin is `data-layer/tutor/plugins/openedx-elasticsearch.py`.
- `infra/terraform_executable`
  - Removed committed Terraform binary wrapper. Repo now expects standard `terraform` in `PATH`.
- `k8s/03-ingress/openedx-ingress.yaml`
  - Removed assessment fallback ingress (placeholder `.local` domains).
- `k8s/03-ingress/create-selfsigned-tls.sh`
  - Removed assessment fallback self-signed TLS helper.
- `k8s/01-echo-ingress.yaml`
  - Removed optional sanity ingress to keep the repo lean and production-path only.

## Kept Intentionally (still useful)

- `infra/ses/`
  - Optional but production-relevant if account activation email flow is enabled.
