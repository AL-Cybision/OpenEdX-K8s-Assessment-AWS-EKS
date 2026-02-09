#!/usr/bin/env bash
set -euo pipefail

# Wrapper to apply Tutor k8s manifests and permanently remove Caddy resources
# while keeping NGINX ingress as the edge proxy.

TUTOR_BIN="${TUTOR_BIN:-.venv/bin/tutor}"
NAMESPACE="${NAMESPACE:-openedx-prod}"
TUTOR_ENV_DIR="${TUTOR_ENV_DIR:-${HOME}/.local/share/tutor/env}"

"${TUTOR_BIN}" config save --env-only

# Render manifests via kustomize, remove Caddy resources and Jobs/Namespaces,
# then apply to the cluster.
kubectl kustomize "${TUTOR_ENV_DIR}" | \
  "${TUTOR_BIN%/tutor}/python3" infra/k8s/04-tutor-apply/postrender-remove-caddy.py | \
  kubectl -n "${NAMESPACE}" apply -f -

echo "Tutor manifests applied (Caddy removed via post-render filter)."
