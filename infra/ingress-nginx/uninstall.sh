#!/usr/bin/env bash
set -euo pipefail

# Removes ingress-nginx Helm release from ingress-nginx namespace.

helm -n ingress-nginx uninstall ingress-nginx || true

