#!/usr/bin/env bash
set -euo pipefail

# Removes ingress-nginx Helm release from ingress-nginx namespace.

# Best-effort uninstall to keep script idempotent during repeated cleanup.
helm -n ingress-nginx uninstall ingress-nginx || true
