#!/usr/bin/env bash
set -euo pipefail

# Installs/updates observability stack (kube-prometheus-stack + loki-stack).

# Namespace and values file paths for both Helm releases.
NAMESPACE="observability"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VALUES_KPS="${REPO_ROOT}/configs/observability/values-kube-prometheus-stack.yaml"
VALUES_LOKI="${REPO_ROOT}/configs/observability/values-loki-stack.yaml"
RULES_FILE="${REPO_ROOT}/configs/observability/openedx-prometheusrule.yaml"

# Register/update chart repositories.
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install/upgrade metrics/alerts stack (Prometheus, Alertmanager, Grafana, exporters).
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "${NAMESPACE}" --create-namespace \
  -f "${VALUES_KPS}" \
  --wait --timeout 10m

# Install/upgrade Loki + promtail log collection stack.
helm upgrade --install loki-stack grafana/loki-stack \
  -n "${NAMESPACE}" \
  -f "${VALUES_LOKI}" \
  --wait --timeout 10m

# Apply custom Open edX alert rules used for assessment evidence and demo validation.
kubectl apply -f "${RULES_FILE}"
