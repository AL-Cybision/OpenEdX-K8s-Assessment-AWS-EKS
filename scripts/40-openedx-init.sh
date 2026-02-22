#!/usr/bin/env bash
set -euo pipefail

# Deterministic Open edX DB/app init flow for this repo's "external DB + no edge
# Caddy" architecture. We intentionally avoid `tutor k8s init` because that path
# may still execute Meilisearch bootstrap jobs even when RUN_MEILISEARCH=false.

NAMESPACE="${NAMESPACE:-openedx-prod}"

kubectl -n "${NAMESPACE}" rollout status deploy/lms-worker --timeout=600s
kubectl -n "${NAMESPACE}" rollout status deploy/cms-worker --timeout=600s

LMS_WORKER_POD="$(kubectl -n "${NAMESPACE}" get pods -o name | rg '^pod/lms-worker-' | head -n1 | cut -d/ -f2)"
CMS_WORKER_POD="$(kubectl -n "${NAMESPACE}" get pods -o name | rg '^pod/cms-worker-' | head -n1 | cut -d/ -f2)"

if [[ -z "${LMS_WORKER_POD}" || -z "${CMS_WORKER_POD}" ]]; then
  echo "Unable to find lms-worker/cms-worker pods for migration init." >&2
  exit 1
fi

# Apply database schema for both services.
kubectl -n "${NAMESPACE}" exec "${CMS_WORKER_POD}" -c cms-worker -- sh -lc \
  'cd /openedx/edx-platform && /openedx/venv/bin/python manage.py cms migrate --noinput'

kubectl -n "${NAMESPACE}" exec "${LMS_WORKER_POD}" -c lms-worker -- sh -lc \
  'cd /openedx/edx-platform && /openedx/venv/bin/python manage.py lms migrate --noinput'

# Restart web deployments to pick up a fully initialized schema.
kubectl -n "${NAMESPACE}" rollout restart deploy/lms deploy/cms
kubectl -n "${NAMESPACE}" rollout status deploy/lms --timeout=600s
kubectl -n "${NAMESPACE}" rollout status deploy/cms --timeout=600s

echo "Open edX init complete (migrations + web rollout)."
