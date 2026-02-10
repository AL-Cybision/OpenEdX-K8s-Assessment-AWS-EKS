#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }

LB_HOSTNAME=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "${LB_HOSTNAME}" ]; then
  echo "Failed to detect ingress-nginx LB hostname" >&2
  exit 1
fi

echo "Using LB hostname: ${LB_HOSTNAME}"

terraform -chdir="${SCRIPT_DIR}" init -input=false
terraform -chdir="${SCRIPT_DIR}" plan -input=false -out tfplan \
  -var "origin_domain_name=${LB_HOSTNAME}"
terraform -chdir="${SCRIPT_DIR}" apply -input=false tfplan
