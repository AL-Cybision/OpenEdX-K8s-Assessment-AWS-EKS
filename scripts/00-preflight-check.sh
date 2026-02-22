#!/usr/bin/env bash
set -euo pipefail

# Fast preflight that prevents common assessor/runtime failures before deployment:
# - missing local tooling/auth
# - inaccessible EKS API due endpoint CIDR drift (home/public IP changes)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
# If true, automatically re-lock EKS public endpoint to current /32 when needed.
AUTO_FIX_ENDPOINT_CIDR="${AUTO_FIX_ENDPOINT_CIDR:-true}"

for cmd in aws kubectl eksctl helm terraform jq curl; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "Missing required command: ${cmd}" >&2
    exit 1
  }
done

aws sts get-caller-identity >/dev/null

CLUSTER_STATUS="$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'cluster.status' \
  --output text)"
if [[ "${CLUSTER_STATUS}" != "ACTIVE" ]]; then
  echo "EKS cluster ${CLUSTER_NAME} is not ACTIVE (status=${CLUSTER_STATUS})." >&2
  exit 1
fi

CURRENT_PUBLIC_IP="$(curl -fsS --max-time 5 https://checkip.amazonaws.com | tr -d '\n')"
CURRENT_CIDR="${CURRENT_PUBLIC_IP}/32"

PUBLIC_ACCESS="$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'cluster.resourcesVpcConfig.endpointPublicAccess' \
  --output text)"

if [[ "${PUBLIC_ACCESS}" == "True" ]]; then
  if ! aws eks describe-cluster \
      --name "${CLUSTER_NAME}" \
      --region "${AWS_REGION}" \
      --query 'cluster.resourcesVpcConfig.publicAccessCidrs' \
      --output text | tr '\t' '\n' | rg -qx "${CURRENT_CIDR}"; then
    echo "Current IP (${CURRENT_CIDR}) is not allowed on EKS public endpoint."
    if [[ "${AUTO_FIX_ENDPOINT_CIDR}" == "true" ]]; then
      echo "Auto-fixing endpoint CIDR to ${CURRENT_CIDR}..."
      CLUSTER_NAME="${CLUSTER_NAME}" \
      AWS_REGION="${AWS_REGION}" \
      EKS_PUBLIC_ACCESS_CIDRS="${CURRENT_CIDR}" \
        "${REPO_ROOT}/scripts/11-eks-harden-endpoint.sh"
    else
      echo "Run: EKS_PUBLIC_ACCESS_CIDRS=${CURRENT_CIDR} scripts/11-eks-harden-endpoint.sh" >&2
      exit 1
    fi
  fi
fi

# Final API connectivity check after any potential endpoint update.
kubectl get ns >/dev/null

echo "Preflight OK:"
echo "- AWS auth valid"
echo "- EKS cluster ACTIVE (${CLUSTER_NAME}, ${AWS_REGION})"
echo "- kubectl connectivity healthy"
