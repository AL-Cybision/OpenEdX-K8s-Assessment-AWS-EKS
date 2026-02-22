#!/usr/bin/env bash
set -euo pipefail

# Destroys assessment infrastructure in a safe default order.
# Set specific toggles to false if you want partial cleanup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DESTROY_CLOUDFRONT_WAF="${DESTROY_CLOUDFRONT_WAF:-true}"
DESTROY_MEDIA_EFS="${DESTROY_MEDIA_EFS:-true}"
DESTROY_DATA_LAYER="${DESTROY_DATA_LAYER:-true}"
DELETE_EKS_CLUSTER="${DELETE_EKS_CLUSTER:-true}"

if [[ "${DESTROY_CLOUDFRONT_WAF}" == "true" ]]; then
  terraform -chdir="${REPO_ROOT}/configs/cloudfront-waf" init -input=false >/dev/null
  terraform -chdir="${REPO_ROOT}/configs/cloudfront-waf" destroy -auto-approve
fi

if [[ "${DESTROY_MEDIA_EFS}" == "true" ]]; then
  terraform -chdir="${REPO_ROOT}/configs/terraform/media-efs" init -input=false >/dev/null
  terraform -chdir="${REPO_ROOT}/configs/terraform/media-efs" destroy -auto-approve \
    -var "cluster_name=${CLUSTER_NAME:-openedx-eks}" \
    -var "aws_region=${AWS_REGION:-us-east-1}"
fi

if [[ "${DESTROY_DATA_LAYER}" == "true" ]]; then
  "${REPO_ROOT}/scripts/97-data-layer-destroy.sh"
fi

if [[ "${DELETE_EKS_CLUSTER}" == "true" ]]; then
  "${REPO_ROOT}/scripts/98-eks-delete.sh"
fi

echo "Destroy workflow complete."
