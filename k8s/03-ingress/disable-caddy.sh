#!/usr/bin/env bash
set -euo pipefail

kubectl -n openedx-prod delete deployment/caddy service/caddy \
  configmap/caddy-config configmap/mfe-caddy-config --ignore-not-found
