#!/usr/bin/env bash
set -euo pipefail

# Wrapper to apply Tutor k8s manifests and permanently remove Caddy resources
# while keeping NGINX ingress as the edge proxy.

TUTOR_BIN="${TUTOR_BIN:-.venv/bin/tutor}"
NAMESPACE="${NAMESPACE:-openedx-prod}"
TUTOR_ENV_DIR="${TUTOR_ENV_DIR:-${HOME}/.local/share/tutor/env}"
LMS_HOST="${LMS_HOST:-lms.openedx.local}"
CMS_HOST="${CMS_HOST:-studio.openedx.local}"

# Ensure post-render scripts (python) see these values even when defaults are used.
export LMS_HOST CMS_HOST

"${TUTOR_BIN}" config save --env-only

# Render manifests via kustomize, remove Caddy resources and Jobs/Namespaces,
# then apply to the cluster.
kubectl kustomize "${TUTOR_ENV_DIR}" | \
  "${TUTOR_BIN%/tutor}/python3" infra/k8s/04-tutor-apply/postrender-remove-caddy.py | \
  kubectl -n "${NAMESPACE}" apply -f -

# Keep MFE runtime env complete to avoid white-screen config errors in
# learner-dashboard/auth pages when running with placeholder local domains.
kubectl -n "${NAMESPACE}" set env deployment/mfe \
  LOGO_URL="https://${LMS_HOST}/theming/asset/images/logo.png" \
  CREDIT_PURCHASE_URL="https://${LMS_HOST}/dashboard" \
  SUPPORT_EMAIL="contact@${LMS_HOST}" \
  TERMS_OF_SERVICE_URL="https://${LMS_HOST}/tos" \
  PRIVACY_POLICY_URL="https://${LMS_HOST}/privacy" \
  ORDER_HISTORY_URL="https://${LMS_HOST}/dashboard" \
  ENABLE_ACCESSIBILITY_PAGE="false" >/dev/null

# Caddy does not auto-reload configmap updates; ensure the MFE pod picks up the
# latest rendered Caddyfile changes as part of a deterministic apply.
kubectl -n "${NAMESPACE}" rollout restart deployment/mfe >/dev/null || true
kubectl -n "${NAMESPACE}" rollout status deployment/mfe --timeout=240s >/dev/null || true

echo "Tutor manifests applied (Caddy removed via post-render filter)."
