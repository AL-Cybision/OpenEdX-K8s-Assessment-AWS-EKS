#!/usr/bin/env bash
set -euo pipefail

# Applies Open edX-specific PrometheusRule alerts in observability namespace.

kubectl apply -f infra/observability/openedx-prometheusrule.yaml
kubectl -n observability get prometheusrule openedx-prod-rules

