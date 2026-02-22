#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: infra/cost/resume.sh" >&2
echo "[compat] Use: scripts/91-cost-resume.sh" >&2
exec "${REPO_ROOT}/scripts/91-cost-resume.sh" "$@"
