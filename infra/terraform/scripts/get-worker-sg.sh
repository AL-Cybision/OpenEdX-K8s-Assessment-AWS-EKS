#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CLUSTER_NAME=$(echo "$INPUT" | jq -r '.cluster_name')
AWS_REGION=$(echo "$INPUT" | jq -r '.aws_region')

NODEGROUP=$(aws eks list-nodegroups \
  --cluster-name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'nodegroups[0]' \
  --output text)

if [[ -z "$NODEGROUP" || "$NODEGROUP" == "None" ]]; then
  echo '{"error":"No EKS nodegroups found"}'
  exit 0
fi

LT_ID=$(aws eks describe-nodegroup \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP" \
  --region "$AWS_REGION" \
  --query 'nodegroup.launchTemplate.id' \
  --output text)

if [[ -z "$LT_ID" || "$LT_ID" == "None" ]]; then
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
  CLUSTER_SG=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
    --output text)
  SG_ID="$CLUSTER_SG"
fi

echo "{\"security_group_id\":\"$SG_ID\"}"
