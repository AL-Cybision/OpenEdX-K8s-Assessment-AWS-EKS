#!/usr/bin/env bash
set -euo pipefail

# Installs/upgrades ingress-nginx controller using the pinned chart version and repo values.

# Helm release metadata and version pin for reproducibility.
NAMESPACE="ingress-nginx"
RELEASE_NAME="ingress-nginx"
CHART_VERSION="${CHART_VERSION:-4.14.3}"

# Resolve values file from this repository.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/values.yaml"

# Register/update ingress-nginx chart repository.
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install or upgrade ingress controller with repo-managed settings.
helm upgrade --install "${RELEASE_NAME}" ingress-nginx/ingress-nginx \
  -n "${NAMESPACE}" --create-namespace \
  -f "${VALUES_FILE}" \
  --version "${CHART_VERSION}" \
  --wait --timeout 10m
