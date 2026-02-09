#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_BIN="${TF_BIN:-${SCRIPT_DIR}/../terraform_executable}"
if [ ! -x "${TF_BIN}" ]; then
  TF_BIN="$(command -v terraform)"
fi

CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

"${TF_BIN}" -chdir="${SCRIPT_DIR}" init -input=false
"${TF_BIN}" -chdir="${SCRIPT_DIR}" plan -input=false -out tfplan \
  -var "cluster_name=${CLUSTER_NAME}" \
  -var "aws_region=${AWS_REGION}"
"${TF_BIN}" -chdir="${SCRIPT_DIR}" apply -input=false tfplan

