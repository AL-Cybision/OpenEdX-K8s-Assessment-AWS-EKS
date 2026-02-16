#!/usr/bin/env bash
set -euo pipefail

# Creates the EKS cluster from template and updates local kubeconfig.
# Optionally chains into install-core-addons.sh for mandatory add-ons.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/cluster.yaml"

CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
K8S_VERSION="${K8S_VERSION:-1.33}"
INSTALL_CORE_ADDONS="${INSTALL_CORE_ADDONS:-true}"
EKS_PUBLIC_ACCESS_CIDRS="${EKS_PUBLIC_ACCESS_CIDRS:-}"

TMP_CFG="$(mktemp)"
trap 'rm -f "${TMP_CFG}"' EXIT

if [ -z "${EKS_PUBLIC_ACCESS_CIDRS}" ]; then
  DETECTED_PUBLIC_IP="$(curl -fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '\n' || true)"
  if [[ "${DETECTED_PUBLIC_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    EKS_PUBLIC_ACCESS_CIDRS="${DETECTED_PUBLIC_IP}/32"
  else
    echo "Unable to auto-detect public IP. Set EKS_PUBLIC_ACCESS_CIDRS (comma-separated CIDRs)." >&2
    exit 1
  fi
fi

CIDR_BLOCK=""
IFS=',' read -r -a CIDR_LIST <<< "${EKS_PUBLIC_ACCESS_CIDRS}"
for CIDR in "${CIDR_LIST[@]}"; do
  CIDR="$(echo "${CIDR}" | xargs)"
  if [ -z "${CIDR}" ]; then
    continue
  fi
  CIDR_BLOCK+="      - ${CIDR}"$'\n'
done

if [ -z "${CIDR_BLOCK}" ]; then
  echo "No valid CIDRs found in EKS_PUBLIC_ACCESS_CIDRS." >&2
  exit 1
fi

sed -e "s/__CLUSTER_NAME__/${CLUSTER_NAME}/g" \
    -e "s/__AWS_REGION__/${AWS_REGION}/g" \
    -e "s/__K8S_VERSION__/${K8S_VERSION}/g" \
    "${TEMPLATE}" \
  | awk -v cidr_block="${CIDR_BLOCK}" '
      {
        if ($0 == "__PUBLIC_ACCESS_CIDRS__") {
          printf "%s", cidr_block
        } else {
          print $0
        }
      }
    ' > "${TMP_CFG}"

echo "Using EKS public endpoint CIDRs: ${EKS_PUBLIC_ACCESS_CIDRS}"

eksctl create cluster -f "${TMP_CFG}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null
kubectl get ns >/dev/null

if [ "${INSTALL_CORE_ADDONS}" = "true" ]; then
  "${SCRIPT_DIR}/install-core-addons.sh"
fi

echo "EKS cluster ready: ${CLUSTER_NAME} (${AWS_REGION})"
