#!/usr/bin/env bash
set -euo pipefail

# Refreshes local kubeconfig context for the target EKS cluster.

# Target cluster identity (override via env as needed).
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Merge/refresh kubeconfig entry so kubectl can talk to this cluster.
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
