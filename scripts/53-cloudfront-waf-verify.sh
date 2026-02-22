#!/usr/bin/env bash
set -euo pipefail

# Verifies CloudFront/WAF behavior: baseline request and blocked header request.

# Resolve Terraform module path and verify CLI availability.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/configs/cloudfront-waf"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found in PATH" >&2; exit 1; }

# Ensure providers/state metadata are initialized before reading outputs.
terraform -chdir="${TF_DIR}" init -input=false >/dev/null

CF_DOMAIN="$(terraform -chdir="${TF_DIR}" output -json | jq -r '.cloudfront_domain_name.value // empty')"

if [ -z "${CF_DOMAIN}" ]; then
  echo "CloudFront domain output not found. Run scripts/52-cloudfront-waf-apply.sh first." >&2
  exit 1
fi

echo "CloudFront domain: ${CF_DOMAIN}"

printf "\nExpected non-403 (no WAF block):\n"
# Baseline request should return non-403 (often 200/301/404 depending on app route).
curl -sSI "https://${CF_DOMAIN}/" | head -n 5

printf "\nExpected 403 (WAF block):\n"
# Header-triggered rule must return 403 to prove WAF enforcement.
curl -sSI -H "X-Block-Me: 1" "https://${CF_DOMAIN}/" | head -n 5
