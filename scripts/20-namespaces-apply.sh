#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

kubectl apply -f "${REPO_ROOT}/configs/k8s/namespaces.yaml"
kubectl get ns openedx-prod ingress-nginx observability
