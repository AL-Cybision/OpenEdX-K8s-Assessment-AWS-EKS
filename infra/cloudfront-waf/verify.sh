#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: infra/cloudfront-waf/verify.sh" >&2
echo "[compat] Use: scripts/53-cloudfront-waf-verify.sh" >&2
exec "${REPO_ROOT}/scripts/53-cloudfront-waf-verify.sh" "$@"
