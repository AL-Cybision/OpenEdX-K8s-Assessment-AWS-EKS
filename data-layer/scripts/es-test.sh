#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: data-layer/scripts/es-test.sh" >&2
echo "[compat] Use: scripts/70-es-test.sh" >&2
exec "${REPO_ROOT}/scripts/70-es-test.sh" "$@"
