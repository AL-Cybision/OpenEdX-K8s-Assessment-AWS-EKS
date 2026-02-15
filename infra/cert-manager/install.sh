#!/usr/bin/env bash
set -euo pipefail

# Installs cert-manager (used for production-style TLS via Let's Encrypt).
# This is optional for the assessment runbook, but recommended for real domains
# to avoid browser issues from self-signed certificates.

NAMESPACE="${NAMESPACE:-cert-manager}"
RELEASE="${RELEASE:-cert-manager}"
CHART_VERSION="${CHART_VERSION:-v1.19.3}"

helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo update >/dev/null

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}" >/dev/null

helm upgrade --install "${RELEASE}" jetstack/cert-manager \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --set crds.enabled=true

kubectl -n "${NAMESPACE}" rollout status deploy/cert-manager --timeout=10m
kubectl -n "${NAMESPACE}" rollout status deploy/cert-manager-webhook --timeout=10m
kubectl -n "${NAMESPACE}" rollout status deploy/cert-manager-cainjector --timeout=10m

