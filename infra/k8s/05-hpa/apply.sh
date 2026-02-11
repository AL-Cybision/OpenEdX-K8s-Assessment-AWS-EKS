#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-openedx-prod}"
LMS_CPU_REQUEST="${LMS_CPU_REQUEST:-200m}"
LMS_MEM_REQUEST="${LMS_MEM_REQUEST:-1Gi}"
LMS_CPU_LIMIT="${LMS_CPU_LIMIT:-1000m}"
LMS_MEM_LIMIT="${LMS_MEM_LIMIT:-2Gi}"
CMS_CPU_REQUEST="${CMS_CPU_REQUEST:-200m}"
CMS_MEM_REQUEST="${CMS_MEM_REQUEST:-1Gi}"
CMS_CPU_LIMIT="${CMS_CPU_LIMIT:-1000m}"
CMS_MEM_LIMIT="${CMS_MEM_LIMIT:-2Gi}"

if ! kubectl top nodes >/dev/null 2>&1; then
  echo "metrics-server is not ready (kubectl top failed); run infra/eksctl/install-core-addons.sh first." >&2
  exit 1
fi

# Ensure CPU requests/limits exist for HPA to work.
# Defaults are sized to be reproducible on a 2x t3.large cluster.
kubectl -n "${NAMESPACE}" set resources deployment/lms \
  --requests=cpu="${LMS_CPU_REQUEST}",memory="${LMS_MEM_REQUEST}" \
  --limits=cpu="${LMS_CPU_LIMIT}",memory="${LMS_MEM_LIMIT}"

kubectl -n "${NAMESPACE}" set resources deployment/cms \
  --requests=cpu="${CMS_CPU_REQUEST}",memory="${CMS_MEM_REQUEST}" \
  --limits=cpu="${CMS_CPU_LIMIT}",memory="${CMS_MEM_LIMIT}"

# Wait until new pods with resource requests are rolled out.
kubectl -n "${NAMESPACE}" rollout status deployment/lms --timeout=10m
kubectl -n "${NAMESPACE}" rollout status deployment/cms --timeout=10m

kubectl apply -f infra/k8s/05-hpa/lms-hpa.yaml
kubectl apply -f infra/k8s/05-hpa/cms-hpa.yaml

kubectl -n "${NAMESPACE}" get hpa
