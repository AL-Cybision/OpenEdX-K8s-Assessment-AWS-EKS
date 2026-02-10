#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }

CF_DOMAIN=$(terraform -chdir="${SCRIPT_DIR}" output -raw cloudfront_domain_name)

if [ -z "${CF_DOMAIN}" ]; then
  echo "CloudFront domain not found" >&2
  exit 1
fi

echo "CloudFront domain: ${CF_DOMAIN}"

printf "\nExpected non-403 (no WAF block):\n"
curl -sSI "https://${CF_DOMAIN}/" | head -n 5

printf "\nExpected 403 (WAF block):\n"
curl -sSI -H "X-Block-Me: 1" "https://${CF_DOMAIN}/" | head -n 5
