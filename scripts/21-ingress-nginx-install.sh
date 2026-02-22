#!/usr/bin/env bash
set -euo pipefail

# Installs/upgrades ingress-nginx controller using the pinned chart version and repo values.

# Helm release metadata and version pin for reproducibility.
NAMESPACE="ingress-nginx"
RELEASE_NAME="ingress-nginx"
CHART_VERSION="${CHART_VERSION:-4.14.3}"

# Resolve values file from this repository.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALUES_FILE="${REPO_ROOT}/configs/ingress-nginx/values.yaml"

# Register/update ingress-nginx chart repository.
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install or upgrade ingress controller with repo-managed settings.
# Retry a few times because EKS API connections can transiently drop during long
# helm operations ("client connection lost").
ATTEMPTS=3
for ((i=1; i<=ATTEMPTS; i++)); do
  set +e
  helm upgrade --install "${RELEASE_NAME}" ingress-nginx/ingress-nginx \
    -n "${NAMESPACE}" --create-namespace \
    -f "${VALUES_FILE}" \
    --version "${CHART_VERSION}" \
    --wait --timeout 10m
  RC=$?
  set -e
  if [ ${RC} -eq 0 ]; then
    exit 0
  fi
  if [ ${i} -lt ${ATTEMPTS} ]; then
    echo "Helm install/upgrade failed (attempt ${i}/${ATTEMPTS}); retrying in 10s..." >&2
    sleep 10
  else
    exit ${RC}
  fi
done
