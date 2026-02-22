#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: infra/preflight/check.sh" >&2
echo "[compat] Use: scripts/00-preflight-check.sh" >&2
exec "${REPO_ROOT}/scripts/00-preflight-check.sh" "$@"
