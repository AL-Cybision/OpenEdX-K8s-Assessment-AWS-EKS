#!/usr/bin/env bash
set -euo pipefail

helm -n ingress-nginx uninstall ingress-nginx || true

