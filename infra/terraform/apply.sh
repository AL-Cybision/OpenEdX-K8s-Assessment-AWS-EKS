#!/usr/bin/env bash
set -euo pipefail

# Provisions external data layer (RDS MySQL + EC2 Mongo/Redis/Elasticsearch).

# Resolve script-local Terraform directory and verify tool is installed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }

# Default deployment identity; override for alternate cluster/region.
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Initialize providers/modules and local state.
terraform -chdir="${SCRIPT_DIR}" init -input=false
# Build an execution plan pinned to the target cluster/region inputs.
terraform -chdir="${SCRIPT_DIR}" plan -input=false -out tfplan \
  -var "cluster_name=${CLUSTER_NAME}" \
  -var "aws_region=${AWS_REGION}"
# Apply exactly the reviewed plan file for deterministic provisioning.
terraform -chdir="${SCRIPT_DIR}" apply -input=false tfplan
