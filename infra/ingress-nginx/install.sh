#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="ingress-nginx"
RELEASE_NAME="ingress-nginx"
CHART_VERSION="${CHART_VERSION:-4.14.3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/values.yaml"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install "${RELEASE_NAME}" ingress-nginx/ingress-nginx \
  -n "${NAMESPACE}" --create-namespace \
  -f "${VALUES_FILE}" \
  --version "${CHART_VERSION}" \
  --wait --timeout 10m

