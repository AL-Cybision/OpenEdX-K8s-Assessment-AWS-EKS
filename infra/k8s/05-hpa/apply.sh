#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-openedx-prod}"

# Ensure CPU requests/limits exist for HPA to work.
# Adjust values if needed for your node size.
kubectl -n "${NAMESPACE}" set resources deployment/lms \
  --requests=cpu=200m,memory=2Gi --limits=cpu=1000m,memory=3Gi

kubectl -n "${NAMESPACE}" set resources deployment/cms \
  --requests=cpu=200m,memory=2Gi --limits=cpu=1000m,memory=3Gi

kubectl apply -f infra/k8s/05-hpa/lms-hpa.yaml
kubectl apply -f infra/k8s/05-hpa/cms-hpa.yaml
