#!/usr/bin/env bash
set -euo pipefail

# Installs/updates observability stack (kube-prometheus-stack + loki-stack).

NAMESPACE="observability"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VALUES_KPS="${REPO_ROOT}/infra/observability/values-kube-prometheus-stack.yaml"
VALUES_LOKI="${REPO_ROOT}/infra/observability/values-loki-stack.yaml"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "${NAMESPACE}" --create-namespace \
  -f "${VALUES_KPS}" \
  --wait --timeout 10m

helm upgrade --install loki-stack grafana/loki-stack \
  -n "${NAMESPACE}" \
  -f "${VALUES_LOKI}" \
  --wait --timeout 10m
