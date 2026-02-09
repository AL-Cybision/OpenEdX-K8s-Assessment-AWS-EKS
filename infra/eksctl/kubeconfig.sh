#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
