#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --wait
