#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: infra/k8s/04-tutor-apply/init.sh" >&2
echo "[compat] Use: scripts/40-openedx-init.sh" >&2
exec "${REPO_ROOT}/scripts/40-openedx-init.sh" "$@"
