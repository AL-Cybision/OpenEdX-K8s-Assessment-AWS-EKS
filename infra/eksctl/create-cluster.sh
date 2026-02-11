#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/cluster.yaml"

CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
K8S_VERSION="${K8S_VERSION:-1.33}"
INSTALL_CORE_ADDONS="${INSTALL_CORE_ADDONS:-true}"

TMP_CFG="$(mktemp)"
trap 'rm -f "${TMP_CFG}"' EXIT

sed -e "s/__CLUSTER_NAME__/${CLUSTER_NAME}/g" \
    -e "s/__AWS_REGION__/${AWS_REGION}/g" \
    -e "s/__K8S_VERSION__/${K8S_VERSION}/g" \
    "${TEMPLATE}" > "${TMP_CFG}"

eksctl create cluster -f "${TMP_CFG}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null
kubectl get ns >/dev/null

if [ "${INSTALL_CORE_ADDONS}" = "true" ]; then
  "${SCRIPT_DIR}/install-core-addons.sh"
fi

echo "EKS cluster ready: ${CLUSTER_NAME} (${AWS_REGION})"
