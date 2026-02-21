#!/usr/bin/env bash
set -euo pipefail

# Destroys external data-layer resources managed by infra/terraform.

# Resolve script-local Terraform directory and verify tool is installed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }

# Default deployment identity; override for alternate cluster/region.
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Destroy all Terraform-managed data-layer resources for this target.
terraform -chdir="${SCRIPT_DIR}" destroy -input=false -auto-approve \
  -var "cluster_name=${CLUSTER_NAME}" \
  -var "aws_region=${AWS_REGION}"
