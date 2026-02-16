#!/usr/bin/env bash
set -euo pipefail

# Creates point-in-time backups for external data services and EBS-backed PVC volumes.
# Scope: RDS snapshot + EC2 volume snapshots + openedx-prod EBS CSI PV snapshots.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REGION="us-east-1"
TF_DIR="${TF_DIR:-${SCRIPT_DIR}/../terraform}"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }
TS=$(date +%Y%m%d-%H%M%S)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd aws
require_cmd kubectl
require_cmd jq

# --- RDS snapshot ---
RDS_ENDPOINT=$(terraform -chdir="${TF_DIR}" output -raw rds_endpoint)
DB_ID=$(aws rds describe-db-instances --region ${REGION} \
  --query "DBInstances[?Endpoint.Address=='${RDS_ENDPOINT}'].DBInstanceIdentifier | [0]" \
  --output text)

if [ -z "${DB_ID}" ] || [ "${DB_ID}" = "None" ]; then
  echo "Failed to resolve RDS instance from endpoint: ${RDS_ENDPOINT}" >&2
  exit 1
fi

aws rds create-db-snapshot \
  --region ${REGION} \
  --db-instance-identifier "${DB_ID}" \
  --db-snapshot-identifier "${DB_ID}-${TS}"

echo "RDS snapshot created: ${DB_ID}-${TS}"

# --- EC2 DB snapshots (Mongo/Redis/Elasticsearch) ---
for name in mongo redis elasticsearch; do
  ip=$(terraform -chdir="${TF_DIR}" output -raw "${name}_private_ip")
  instance_id=$(aws ec2 describe-instances --region ${REGION} \
    --filters Name=private-ip-address,Values=${ip} \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

  if [ -z "${instance_id}" ] || [ "${instance_id}" = "None" ]; then
    echo "Failed to resolve EC2 instance for ${name} (${ip})" >&2
    exit 1
  fi

  volume_id=$(aws ec2 describe-instances --region ${REGION} \
    --instance-ids ${instance_id} \
    --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
    --output text)

  aws ec2 create-snapshot \
    --region ${REGION} \
    --volume-id ${volume_id} \
    --description "openedx-prod-${name}-${TS}"

  echo "EC2 snapshot created: ${name} ${volume_id}"
done

# --- PVC snapshots (EBS CSI volumes for openedx-prod) ---
# Only snapshot EBS-backed PVs. EFS PVs use a different backup mechanism (AWS Backup).
PV_IDS=$(kubectl get pv -o json | jq -r '.items[]
  | select(.spec.claimRef.namespace=="openedx-prod")
  | select(.spec.csi.driver=="ebs.csi.aws.com")
  | .spec.csi.volumeHandle' | sort -u)

for vid in ${PV_IDS}; do
  aws ec2 create-snapshot \
    --region ${REGION} \
    --volume-id ${vid} \
    --description "openedx-prod-pv-${vid}-${TS}"
  echo "PV snapshot created: ${vid}"
done
