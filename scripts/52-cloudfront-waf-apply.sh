#!/usr/bin/env bash
set -euo pipefail

# Deploys/updates CloudFront + WAF in front of ingress-nginx.
# Includes rerun-safe imports when same-named resources already exist in AWS.

# Resolve Terraform module path and verify required CLIs.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/configs/cloudfront-waf"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws not found in PATH" >&2; exit 1; }

ORIGIN_PROTOCOL_POLICY="${ORIGIN_PROTOCOL_POLICY:-http-only}"
ORIGIN_DOMAIN_NAME="${ORIGIN_DOMAIN_NAME:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
WAF_NAME="${WAF_NAME:-openedx-prod-cf-waf}"
CF_COMMENT="${CF_COMMENT:-OpenEdX NGINX Ingress via CloudFront}"
LB_HOSTNAME="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

if [ -z "${LB_HOSTNAME}" ]; then
  echo "Failed to detect ingress-nginx LB hostname" >&2
  exit 1
fi

if [ -z "${ORIGIN_DOMAIN_NAME}" ]; then
  # Default origin is the ingress service load balancer hostname.
  ORIGIN_DOMAIN_NAME="${LB_HOSTNAME}"
fi

# Guardrail: ELB hostnames do not present certificates matching ELB DNS name.
if [ "${ORIGIN_PROTOCOL_POLICY}" = "https-only" ] && [[ "${ORIGIN_DOMAIN_NAME}" =~ \.elb\..*amazonaws\.com$ ]]; then
  echo "Refusing https-only with ELB hostname origin (${ORIGIN_DOMAIN_NAME})." >&2
  echo "Set ORIGIN_DOMAIN_NAME to a hostname with a trusted certificate (for example lms.yourdomain.com)." >&2
  exit 1
fi

echo "Using origin domain: ${ORIGIN_DOMAIN_NAME}"
echo "Using CloudFront origin protocol policy: ${ORIGIN_PROTOCOL_POLICY}"

# Ensure backend state/providers are initialized.
terraform -chdir="${TF_DIR}" init -input=false

# Rerun safety: if local state is missing but same-named resources exist in AWS,
# import them so plan/apply remains idempotent for assessors.
if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -qx "aws_wafv2_web_acl.this"; then
  EXISTING_WAF_ID="$(aws wafv2 list-web-acls --scope CLOUDFRONT --region "${AWS_REGION}" \
    --query "WebACLs[?Name=='${WAF_NAME}'].Id | [0]" --output text 2>/dev/null || true)"
  if [ -n "${EXISTING_WAF_ID}" ] && [ "${EXISTING_WAF_ID}" != "None" ]; then
    WAF_IMPORT_ID="${EXISTING_WAF_ID}/${WAF_NAME}/CLOUDFRONT"
    echo "Importing existing WAF WebACL into state: ${WAF_IMPORT_ID}"
    terraform -chdir="${TF_DIR}" import -input=false \
      -var "origin_domain_name=${ORIGIN_DOMAIN_NAME}" \
      -var "origin_protocol_policy=${ORIGIN_PROTOCOL_POLICY}" \
      aws_wafv2_web_acl.this "${WAF_IMPORT_ID}" >/dev/null
  fi
fi

if ! terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -qx "aws_cloudfront_distribution.this"; then
  EXISTING_CF_ID="$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='${CF_COMMENT}'].Id | [0]" --output text 2>/dev/null || true)"
  if [ -n "${EXISTING_CF_ID}" ] && [ "${EXISTING_CF_ID}" != "None" ]; then
    echo "Importing existing CloudFront distribution into state: ${EXISTING_CF_ID}"
    terraform -chdir="${TF_DIR}" import -input=false \
      -var "origin_domain_name=${ORIGIN_DOMAIN_NAME}" \
      -var "origin_protocol_policy=${ORIGIN_PROTOCOL_POLICY}" \
      aws_cloudfront_distribution.this "${EXISTING_CF_ID}" >/dev/null
  fi
fi

# Build and apply a reviewed plan for deterministic updates.
terraform -chdir="${TF_DIR}" plan -input=false -out tfplan \
  -var "origin_domain_name=${ORIGIN_DOMAIN_NAME}" \
  -var "origin_protocol_policy=${ORIGIN_PROTOCOL_POLICY}"
terraform -chdir="${TF_DIR}" apply -input=false tfplan
