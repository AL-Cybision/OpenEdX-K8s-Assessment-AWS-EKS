#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"

# External data layer resources (as provisioned by infra/terraform)
RDS_INSTANCE_ID="${RDS_INSTANCE_ID:-openedx-prod-mysql}"
EC2_NAME_PREFIX="${EC2_NAME_PREFIX:-openedx-prod}"

# Node capacity defaults match infra/eksctl/cluster.yaml
NODEGROUP_MIN="${NODEGROUP_MIN:-2}"
NODEGROUP_DESIRED="${NODEGROUP_DESIRED:-2}"
NODEGROUP_MAX="${NODEGROUP_MAX:-3}"

START_RDS="${START_RDS:-true}"
WAIT="${WAIT:-true}"

log() { printf '[resume] %s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd aws

log "region=${AWS_REGION} cluster=${CLUSTER_NAME}"

aws sts get-caller-identity --output json >/dev/null

if [[ "$START_RDS" == "true" ]]; then
  log "Starting RDS instance: ${RDS_INSTANCE_ID}"
  if aws rds describe-db-instances --region "$AWS_REGION" --db-instance-identifier "$RDS_INSTANCE_ID" >/dev/null 2>&1; then
    RDS_STATUS=$(aws rds describe-db-instances --region "$AWS_REGION" --db-instance-identifier "$RDS_INSTANCE_ID" --query 'DBInstances[0].DBInstanceStatus' --output text)
    if [[ "$RDS_STATUS" == "stopped" ]]; then
      aws rds start-db-instance --region "$AWS_REGION" --db-instance-identifier "$RDS_INSTANCE_ID" >/dev/null
      log "RDS start requested"
      if [[ "$WAIT" == "true" ]]; then
        aws rds wait db-instance-available --region "$AWS_REGION" --db-instance-identifier "$RDS_INSTANCE_ID"
        log "RDS instance is available"
      fi
    else
      log "RDS status is '${RDS_STATUS}', skipping start"
    fi
  else
    log "RDS instance not found, skipping"
  fi
else
  log "START_RDS=false (skipping RDS start)"
fi

log "Starting EC2 data-layer instances (tag:Name starts with ${EC2_NAME_PREFIX}-...)"
EC2_FILTERS=(
  "Name=tag:Name,Values=${EC2_NAME_PREFIX}-mongo,${EC2_NAME_PREFIX}-redis,${EC2_NAME_PREFIX}-elasticsearch"
)

# Start only stopped instances. Calling start on "running" instances fails, so
# keep this idempotent.
EC2_IDS_TO_START=$(
  aws ec2 describe-instances --region "$AWS_REGION" \
    --filters "${EC2_FILTERS[@]}" "Name=instance-state-name,Values=stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text
)

EC2_IDS_STOPPING=$(
  aws ec2 describe-instances --region "$AWS_REGION" \
    --filters "${EC2_FILTERS[@]}" "Name=instance-state-name,Values=stopping" \
    --query 'Reservations[].Instances[].InstanceId' --output text
)

if [[ -n "${EC2_IDS_STOPPING// /}" ]]; then
  log "WARNING: Some EC2 instances are in 'stopping' state: ${EC2_IDS_STOPPING}"
  log "         Wait for them to stop, then re-run resume if needed."
fi

if [[ -n "${EC2_IDS_TO_START// /}" ]]; then
  aws ec2 start-instances --region "$AWS_REGION" --instance-ids $EC2_IDS_TO_START >/dev/null
  log "EC2 start requested: $EC2_IDS_TO_START"
  if [[ "$WAIT" == "true" ]]; then
    aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids $EC2_IDS_TO_START
    log "EC2 instances are running"
  fi
else
  log "No stopped EC2 instances found to start (already running/terminated)"
fi

log "Scaling EKS managed nodegroups (min=${NODEGROUP_MIN}, desired=${NODEGROUP_DESIRED}, max=${NODEGROUP_MAX})"
NODEGROUPS=$(aws eks list-nodegroups --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text)
if [[ -z "${NODEGROUPS// /}" ]]; then
  log "No managed nodegroups found (unexpected)."
  exit 1
fi

for ng in $NODEGROUPS; do
  update_id=$(aws eks update-nodegroup-config --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --scaling-config "minSize=${NODEGROUP_MIN},maxSize=${NODEGROUP_MAX},desiredSize=${NODEGROUP_DESIRED}" --query 'update.id' --output text)
  log "nodegroup=${ng} update_id=${update_id}"
done

if [[ "$WAIT" == "true" ]]; then
  log "Waiting for nodegroups to finish updating and nodes to register"
  require_cmd kubectl
  for ng in $NODEGROUPS; do
    while true; do
      st=$(aws eks describe-nodegroup --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --query 'nodegroup.status' --output text)
      [[ "$st" == "ACTIVE" ]] && break
      sleep 10
    done
    log "nodegroup=${ng} status=ACTIVE"
  done

  # Wait for expected node count (best-effort; handles clusters with >1 nodegroup)
  for _ in $(seq 1 60); do
    nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$nodes" -ge "$NODEGROUP_DESIRED" ]]; then
      log "nodes_ready=${nodes}"
      break
    fi
    sleep 10
  done
fi

log "Done. Next: wait for workloads to become Ready:"
log "  kubectl -n ingress-nginx get pods"
log "  kubectl -n openedx-prod get pods"
