#!/usr/bin/env bash
set -euo pipefail

# Terraform external-data helper: resolves the worker security-group ID for SG rules.
# Reads JSON from stdin and writes JSON to stdout (for Terraform external data source).

# Parse external data source input payload.
INPUT=$(cat)
CLUSTER_NAME=$(echo "$INPUT" | jq -r '.cluster_name')
AWS_REGION=$(echo "$INPUT" | jq -r '.aws_region')

# Use first nodegroup as reference for worker networking SG.
NODEGROUP=$(aws eks list-nodegroups \
  --cluster-name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'nodegroups[0]' \
  --output text)

if [[ -z "$NODEGROUP" || "$NODEGROUP" == "None" ]]; then
  # Return structured error object (external data source expects JSON output).
  echo '{"error":"No EKS nodegroups found"}'
  exit 0
fi

# Try to resolve SG from launch template when present.
LT_ID=$(aws eks describe-nodegroup \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP" \
  --region "$AWS_REGION" \
  --query 'nodegroup.launchTemplate.id' \
  --output text)

if [[ -z "$LT_ID" || "$LT_ID" == "None" ]]; then
  # Fallback to cluster shared security group when LT is absent.
  CLUSTER_SG=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
    --output text)
  echo "{\"security_group_id\":\"$CLUSTER_SG\"}"
  exit 0
fi

SG_ID=$(aws ec2 describe-launch-template-versions \
  --launch-template-id "$LT_ID" \
  --versions 1 \
  --region "$AWS_REGION" \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.SecurityGroupIds[0]' \
  --output text)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  # Fallback again to cluster SG if LT has no explicit SG IDs.
  CLUSTER_SG=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
    --output text)
  SG_ID="$CLUSTER_SG"
fi

echo "{\"security_group_id\":\"$SG_ID\"}"
