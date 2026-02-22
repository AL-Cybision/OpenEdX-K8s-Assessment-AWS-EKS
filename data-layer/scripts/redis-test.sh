#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: data-layer/scripts/redis-test.sh" >&2
echo "[compat] Use: scripts/71-redis-test.sh" >&2
exec "${REPO_ROOT}/scripts/71-redis-test.sh" "$@"
