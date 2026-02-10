#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }

CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

terraform -chdir="${SCRIPT_DIR}" init -input=false
terraform -chdir="${SCRIPT_DIR}" plan -input=false -out tfplan \
  -var "cluster_name=${CLUSTER_NAME}" \
  -var "aws_region=${AWS_REGION}"
terraform -chdir="${SCRIPT_DIR}" apply -input=false tfplan
