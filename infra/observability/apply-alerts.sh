#!/usr/bin/env bash
set -euo pipefail

# Applies Open edX-specific PrometheusRule alerts in observability namespace.

# Create/update alert rule CRD object.
kubectl apply -f infra/observability/openedx-prometheusrule.yaml
# Confirm the rule object is present after apply.
kubectl -n observability get prometheusrule openedx-prod-rules
