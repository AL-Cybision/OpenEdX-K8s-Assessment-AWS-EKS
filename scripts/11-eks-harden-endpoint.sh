#!/usr/bin/env bash
set -euo pipefail

# Hardens an existing EKS API endpoint by restricting public CIDRs
# and enabling private endpoint access.

# Target cluster identity; override for non-default clusters.
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_PUBLIC_ACCESS_CIDRS="${EKS_PUBLIC_ACCESS_CIDRS:-}"

# Default behavior: restrict public API endpoint to caller's current IP (/32).
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

# If a prior endpoint update is still in flight, wait until it finishes first.
IN_PROGRESS_UPDATE_ID="$(
  aws eks list-updates \
    --region "${AWS_REGION}" \
    --name "${CLUSTER_NAME}" \
    --query 'updateIds[-1]' \
    --output text 2>/dev/null || true
)"
if [[ -n "${IN_PROGRESS_UPDATE_ID}" && "${IN_PROGRESS_UPDATE_ID}" != "None" ]]; then
  UPDATE_STATUS="$(
    aws eks describe-update \
      --region "${AWS_REGION}" \
      --name "${CLUSTER_NAME}" \
      --update-id "${IN_PROGRESS_UPDATE_ID}" \
      --query 'update.status' \
      --output text 2>/dev/null || true
  )"
  if [[ "${UPDATE_STATUS}" == "InProgress" ]]; then
    echo "Waiting for in-progress EKS update ${IN_PROGRESS_UPDATE_ID}..."
    aws eks wait cluster-active --region "${AWS_REGION}" --name "${CLUSTER_NAME}"
  fi
fi

# Capture update output so we can handle idempotent reruns cleanly.
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
  if echo "${UPDATE_OUTPUT}" | grep -q "ResourceInUseException"; then
    echo "Another EKS endpoint update is currently in progress; waiting and continuing."
    aws eks wait cluster-active --region "${AWS_REGION}" --name "${CLUSTER_NAME}"
  elif echo "${UPDATE_OUTPUT}" | grep -q "already at the desired configuration"; then
    echo "Cluster endpoint already matches requested hardening settings."
  else
    echo "${UPDATE_OUTPUT}" >&2
    exit ${UPDATE_EXIT}
  fi
fi

# Wait until control plane reports ACTIVE again after endpoint update.
aws eks wait cluster-active --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# Print effective endpoint access policy for operator verification.
aws eks describe-cluster \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}" \
  --query 'cluster.resourcesVpcConfig.{endpointPublicAccess:endpointPublicAccess,endpointPrivateAccess:endpointPrivateAccess,publicAccessCidrs:publicAccessCidrs}' \
  --output table
