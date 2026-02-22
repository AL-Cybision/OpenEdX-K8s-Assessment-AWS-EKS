#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
echo "[compat] Deprecated path: k8s/03-ingress/real-domain/apply.sh" >&2
echo "[compat] Use: scripts/41-real-domain-ingress-apply.sh" >&2
exec "${REPO_ROOT}/scripts/41-real-domain-ingress-apply.sh" "$@"
