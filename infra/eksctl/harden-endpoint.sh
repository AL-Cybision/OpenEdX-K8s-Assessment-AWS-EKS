#!/usr/bin/env bash
set -euo pipefail

# Hardens an existing EKS API endpoint by restricting public CIDRs
# and enabling private endpoint access.

CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_PUBLIC_ACCESS_CIDRS="${EKS_PUBLIC_ACCESS_CIDRS:-}"

if [ -z "${EKS_PUBLIC_ACCESS_CIDRS}" ]; then
  DETECTED_PUBLIC_IP="$(curl -fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '\n' || true)"
  if [[ "${DETECTED_PUBLIC_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    EKS_PUBLIC_ACCESS_CIDRS="${DETECTED_PUBLIC_IP}/32"
  else
    echo "Unable to auto-detect public IP. Set EKS_PUBLIC_ACCESS_CIDRS (comma-separated CIDRs)." >&2
    exit 1
  fi
fi

echo "Applying endpoint hardening to cluster ${CLUSTER_NAME} in ${AWS_REGION}"
echo "Public CIDRs: ${EKS_PUBLIC_ACCESS_CIDRS}"

set +e
UPDATE_OUTPUT="$(aws eks update-cluster-config \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}" \
  --resources-vpc-config \
  "endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs=${EKS_PUBLIC_ACCESS_CIDRS}" \
  2>&1)"
UPDATE_EXIT=$?
set -e

if [ ${UPDATE_EXIT} -ne 0 ]; then
  if echo "${UPDATE_OUTPUT}" | grep -q "already at the desired configuration"; then
    echo "Cluster endpoint already matches requested hardening settings."
  else
    echo "${UPDATE_OUTPUT}" >&2
    exit ${UPDATE_EXIT}
  fi
fi

aws eks wait cluster-active --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

aws eks describe-cluster \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}" \
  --query 'cluster.resourcesVpcConfig.{endpointPublicAccess:endpointPublicAccess,endpointPrivateAccess:endpointPrivateAccess,publicAccessCidrs:publicAccessCidrs}' \
  --output table
