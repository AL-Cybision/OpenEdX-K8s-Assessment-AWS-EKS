#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f infra/observability/openedx-prometheusrule.yaml
kubectl -n observability get prometheusrule openedx-prod-rules

