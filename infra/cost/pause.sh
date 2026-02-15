#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"

# External data layer resources (as provisioned by infra/terraform)
RDS_INSTANCE_ID="${RDS_INSTANCE_ID:-openedx-prod-mysql}"
EC2_NAME_PREFIX="${EC2_NAME_PREFIX:-openedx-prod}"

STOP_RDS="${STOP_RDS:-true}"
WAIT="${WAIT:-false}"

log() { printf '[pause] %s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd aws

log "region=${AWS_REGION} cluster=${CLUSTER_NAME}"

aws sts get-caller-identity --output json >/dev/null

log "Stopping EC2 data-layer instances (tag:Name starts with ${EC2_NAME_PREFIX}-...)"
EC2_IDS=$(
  aws ec2 describe-instances --region "$AWS_REGION" \
    --filters "Name=tag:Name,Values=${EC2_NAME_PREFIX}-mongo,${EC2_NAME_PREFIX}-redis,${EC2_NAME_PREFIX}-elasticsearch" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text
)

if [[ -n "${EC2_IDS// /}" ]]; then
  aws ec2 stop-instances --region "$AWS_REGION" --instance-ids $EC2_IDS >/dev/null
  log "EC2 stop requested: $EC2_IDS"
  if [[ "$WAIT" == "true" ]]; then
    aws ec2 wait instance-stopped --region "$AWS_REGION" --instance-ids $EC2_IDS
    log "EC2 instances are stopped"
  fi
else
  log "No EC2 instances found to stop (already terminated or tag mismatch)"
fi

if [[ "$STOP_RDS" == "true" ]]; then
  log "Stopping RDS instance: ${RDS_INSTANCE_ID}"
  if aws rds describe-db-instances --region "$AWS_REGION" --db-instance-identifier "$RDS_INSTANCE_ID" >/dev/null 2>&1; then
    RDS_STATUS=$(aws rds describe-db-instances --region "$AWS_REGION" --db-instance-identifier "$RDS_INSTANCE_ID" --query 'DBInstances[0].DBInstanceStatus' --output text)
    if [[ "$RDS_STATUS" == "available" ]]; then
      aws rds stop-db-instance --region "$AWS_REGION" --db-instance-identifier "$RDS_INSTANCE_ID" >/dev/null
      log "RDS stop requested"
      if [[ "$WAIT" == "true" ]]; then
        aws rds wait db-instance-stopped --region "$AWS_REGION" --db-instance-identifier "$RDS_INSTANCE_ID"
        log "RDS instance is stopped"
      fi
    else
      log "RDS status is '${RDS_STATUS}', skipping stop"
    fi
  else
    log "RDS instance not found, skipping"
  fi
else
  log "STOP_RDS=false (skipping RDS stop)"
fi

log "Scaling EKS managed nodegroups to 0 (min=0, desired=0)"
NODEGROUPS=$(aws eks list-nodegroups --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text)
if [[ -z "${NODEGROUPS// /}" ]]; then
  log "No managed nodegroups found (unexpected)."
  exit 1
fi

for ng in $NODEGROUPS; do
  max=$(aws eks describe-nodegroup --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --query 'nodegroup.scalingConfig.maxSize' --output text)
  update_id=$(aws eks update-nodegroup-config --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --scaling-config "minSize=0,maxSize=${max},desiredSize=0" --query 'update.id' --output text)
  log "nodegroup=${ng} update_id=${update_id}"
done

if [[ "$WAIT" == "true" ]]; then
  log "Waiting for nodegroups to finish updating (this can take a few minutes)"
  for ng in $NODEGROUPS; do
    while true; do
      st=$(aws eks describe-nodegroup --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --query 'nodegroup.status' --output text)
      [[ "$st" == "ACTIVE" ]] && break
      sleep 10
    done
    log "nodegroup=${ng} status=ACTIVE"
  done
fi

log "Done. Baseline costs still apply (EKS control plane, NAT Gateway, Load Balancer, EFS/RDS storage)."

