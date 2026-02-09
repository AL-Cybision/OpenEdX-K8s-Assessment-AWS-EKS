#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_BIN="${TF_BIN:-${SCRIPT_DIR}/../terraform_executable}"
if [ ! -x "${TF_BIN}" ]; then
  TF_BIN="$(command -v terraform)"
fi

LB_HOSTNAME=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "${LB_HOSTNAME}" ]; then
  echo "Failed to detect ingress-nginx LB hostname" >&2
  exit 1
fi

echo "Using LB hostname: ${LB_HOSTNAME}"

"${TF_BIN}" -chdir="${SCRIPT_DIR}" init -input=false
"${TF_BIN}" -chdir="${SCRIPT_DIR}" plan -input=false -out tfplan \
  -var "origin_domain_name=${LB_HOSTNAME}"
"${TF_BIN}" -chdir="${SCRIPT_DIR}" apply -input=false tfplan
