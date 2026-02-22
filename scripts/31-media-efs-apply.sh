#!/usr/bin/env bash
set -euo pipefail

# Provisions EFS + EFS CSI prerequisites for shared Open edX media storage (RWX).

# Resolve script-local Terraform directory and verify tool is installed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/configs/terraform/media-efs"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws not found in PATH" >&2; exit 1; }

# Default deployment identity; override for alternate cluster/region.
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-openedx}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
NAME_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

tf_state_has() {
  terraform -chdir="${TF_DIR}" state list 2>/dev/null | rg -qx "$1"
}

tf_try_import() {
  local resource="$1"
  local import_id="$2"
  if tf_state_has "${resource}"; then
    return 0
  fi
  terraform -chdir="${TF_DIR}" import "${resource}" "${import_id}" >/dev/null
}

# Initialize providers/modules and local state.
terraform -chdir="${TF_DIR}" init -input=false

# Reused-account idempotency: import known singleton resources if they already exist.
if aws iam get-role --role-name "${NAME_PREFIX}-efs-csi-driver" >/dev/null 2>&1; then
  echo "Importing existing IAM role into state: aws_iam_role.efs_csi_driver"
  tf_try_import "aws_iam_role.efs_csi_driver" "${NAME_PREFIX}-efs-csi-driver"
fi

if aws iam list-attached-role-policies \
  --role-name "${NAME_PREFIX}-efs-csi-driver" \
  --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy'] | length(@)" \
  --output text 2>/dev/null | rg -qx '[1-9][0-9]*'; then
  echo "Importing existing IAM attachment into state: aws_iam_role_policy_attachment.efs_csi_driver"
  tf_try_import \
    "aws_iam_role_policy_attachment.efs_csi_driver" \
    "${NAME_PREFIX}-efs-csi-driver/arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
fi

if aws eks describe-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --addon-name aws-efs-csi-driver >/dev/null 2>&1; then
  echo "Importing existing EKS addon into state: aws_eks_addon.efs_csi_driver"
  tf_try_import "aws_eks_addon.efs_csi_driver" "${CLUSTER_NAME}:aws-efs-csi-driver"
fi

# Build an execution plan pinned to the target cluster/region inputs.
terraform -chdir="${TF_DIR}" plan -input=false -out tfplan \
  -var "cluster_name=${CLUSTER_NAME}" \
  -var "aws_region=${AWS_REGION}"
# Apply exactly the reviewed plan file for deterministic provisioning.
terraform -chdir="${TF_DIR}" apply -input=false tfplan
