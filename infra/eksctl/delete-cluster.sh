#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: infra/eksctl/delete-cluster.sh" >&2
echo "[compat] Use: scripts/98-eks-delete.sh" >&2
exec "${REPO_ROOT}/scripts/98-eks-delete.sh" "$@"
