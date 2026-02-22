#!/usr/bin/env bash
set -euo pipefail

# Deletes the EKS cluster and waits for teardown completion.

# Target cluster identity (override via env for non-default stacks).
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Delete cluster and block until cloud resources are fully torn down.
eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --wait
