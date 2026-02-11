#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws not found in PATH" >&2; exit 1; }

LB_HOSTNAME=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ORIGIN_PROTOCOL_POLICY="${ORIGIN_PROTOCOL_POLICY:-http-only}"
AWS_REGION="${AWS_REGION:-us-east-1}"
WAF_NAME="${WAF_NAME:-openedx-prod-cf-waf}"
CF_COMMENT="${CF_COMMENT:-OpenEdX NGINX Ingress via CloudFront}"

if [ -z "${LB_HOSTNAME}" ]; then
  echo "Failed to detect ingress-nginx LB hostname" >&2
  exit 1
fi

echo "Using LB hostname: ${LB_HOSTNAME}"
echo "Using CloudFront origin protocol policy: ${ORIGIN_PROTOCOL_POLICY}"

terraform -chdir="${SCRIPT_DIR}" init -input=false

# Rerun safety: if local state is missing but same-named resources exist in AWS,
# import them so plan/apply remains idempotent for assessors.
if ! terraform -chdir="${SCRIPT_DIR}" state list 2>/dev/null | grep -qx "aws_wafv2_web_acl.this"; then
  EXISTING_WAF_ARN="$(aws wafv2 list-web-acls --scope CLOUDFRONT --region "${AWS_REGION}" \
    --query "WebACLs[?Name=='${WAF_NAME}'].ARN | [0]" --output text 2>/dev/null || true)"
  if [ -n "${EXISTING_WAF_ARN}" ] && [ "${EXISTING_WAF_ARN}" != "None" ]; then
    echo "Importing existing WAF WebACL into state: ${WAF_NAME}"
    terraform -chdir="${SCRIPT_DIR}" import -input=false \
      -var "origin_domain_name=${LB_HOSTNAME}" \
      -var "origin_protocol_policy=${ORIGIN_PROTOCOL_POLICY}" \
      aws_wafv2_web_acl.this "${EXISTING_WAF_ARN}" >/dev/null
  fi
fi

if ! terraform -chdir="${SCRIPT_DIR}" state list 2>/dev/null | grep -qx "aws_cloudfront_distribution.this"; then
  EXISTING_CF_ID="$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='${CF_COMMENT}'].Id | [0]" --output text 2>/dev/null || true)"
  if [ -n "${EXISTING_CF_ID}" ] && [ "${EXISTING_CF_ID}" != "None" ]; then
    echo "Importing existing CloudFront distribution into state: ${EXISTING_CF_ID}"
    terraform -chdir="${SCRIPT_DIR}" import -input=false \
      -var "origin_domain_name=${LB_HOSTNAME}" \
      -var "origin_protocol_policy=${ORIGIN_PROTOCOL_POLICY}" \
      aws_cloudfront_distribution.this "${EXISTING_CF_ID}" >/dev/null
  fi
fi

terraform -chdir="${SCRIPT_DIR}" plan -input=false -out tfplan \
  -var "origin_domain_name=${LB_HOSTNAME}" \
  -var "origin_protocol_policy=${ORIGIN_PROTOCOL_POLICY}"
terraform -chdir="${SCRIPT_DIR}" apply -input=false tfplan
