#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: infra/backups/backup.sh" >&2
echo "[compat] Use: scripts/60-backup-run.sh" >&2
exec "${REPO_ROOT}/scripts/60-backup-run.sh" "$@"
