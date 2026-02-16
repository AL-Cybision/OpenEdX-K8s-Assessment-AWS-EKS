#!/usr/bin/env bash
set -euo pipefail

# Controlled restore helper (dry-run by default) for RDS and EBS snapshots.
# Set CONFIRM_RESTORE=YES to execute restore actions.

REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

TF_DIR="${TF_DIR:-${SCRIPT_DIR}/../terraform}"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  infra/backups/restore.sh rds
    Restores a new RDS instance from the most recent manual snapshot.

    Optional env vars:
      AWS_REGION=us-east-1
      DB_ID=<db-instance-identifier>              (auto-discovered if Terraform state exists)
      SNAPSHOT_ID=<db-snapshot-identifier>        (defaults to latest manual snapshot)
      RESTORE_DB_ID=<new-db-instance-identifier>  (defaults to <DB_ID>-restore-<timestamp>)
      CONFIRM_RESTORE=YES                         (required to execute; otherwise prints commands)

  infra/backups/restore.sh ebs-volume <SNAPSHOT_ID> <AZ>
    Creates a new EBS volume from a snapshot in the given AZ.

    Optional env vars:
      AWS_REGION=us-east-1
      CONFIRM_RESTORE=YES                         (required to execute; otherwise prints commands)
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd aws
require_cmd jq

confirm_or_print() {
  if [ "${CONFIRM_RESTORE:-}" != "YES" ]; then
    echo "Dry run only (no resources created)."
    echo "Set CONFIRM_RESTORE=YES to execute."
    return 1
  fi
  return 0
}

cmd="${1:-}"
shift || true

case "${cmd}" in
  rds)
    DB_ID="${DB_ID:-}"
    if [ -z "${DB_ID}" ]; then
      # Best-effort discovery via Terraform output (requires state).
      if terraform -chdir="${TF_DIR}" output -raw rds_endpoint >/dev/null 2>&1; then
        RDS_ENDPOINT="$(terraform -chdir="${TF_DIR}" output -raw rds_endpoint)"
        DB_ID="$(aws rds describe-db-instances --region "${REGION}" \
          --query "DBInstances[?Endpoint.Address=='${RDS_ENDPOINT}'].DBInstanceIdentifier | [0]" \
          --output text)"
      fi
    fi

    if [ -z "${DB_ID}" ] || [ "${DB_ID}" = "None" ]; then
      echo "Could not determine DB_ID. Set DB_ID=<db-instance-identifier> and retry." >&2
      exit 2
    fi

    SNAPSHOT_ID="${SNAPSHOT_ID:-}"
    if [ -z "${SNAPSHOT_ID}" ]; then
      SNAPSHOT_ID="$(aws rds describe-db-snapshots --region "${REGION}" \
        --db-instance-identifier "${DB_ID}" \
        --snapshot-type manual \
        --query "reverse(sort_by(DBSnapshots,&SnapshotCreateTime))[0].DBSnapshotIdentifier" \
        --output text)"
    fi

    if [ -z "${SNAPSHOT_ID}" ] || [ "${SNAPSHOT_ID}" = "None" ]; then
      echo "No manual snapshots found for ${DB_ID}. Run infra/backups/backup.sh or set SNAPSHOT_ID." >&2
      exit 3
    fi

    RESTORE_DB_ID="${RESTORE_DB_ID:-${DB_ID}-restore-${TS}}"

    DB_CLASS="$(aws rds describe-db-instances --region "${REGION}" \
      --db-instance-identifier "${DB_ID}" \
      --query "DBInstances[0].DBInstanceClass" \
      --output text)"
    SUBNET_GROUP="$(aws rds describe-db-instances --region "${REGION}" \
      --db-instance-identifier "${DB_ID}" \
      --query "DBInstances[0].DBSubnetGroup.DBSubnetGroupName" \
      --output text)"
    VPC_SG_IDS="$(aws rds describe-db-instances --region "${REGION}" \
      --db-instance-identifier "${DB_ID}" \
      --query "DBInstances[0].VpcSecurityGroups[].VpcSecurityGroupId" \
      --output text)"

    echo "Planned RDS restore:"
    echo "  Source DB:      ${DB_ID}"
    echo "  Snapshot:       ${SNAPSHOT_ID}"
    echo "  New DB ID:      ${RESTORE_DB_ID}"
    echo "  Class:          ${DB_CLASS}"
    echo "  Subnet group:   ${SUBNET_GROUP}"
    echo "  VPC SG IDs:     ${VPC_SG_IDS}"
    echo

    if ! confirm_or_print; then
      echo "Command to execute:"
      echo "aws rds restore-db-instance-from-db-snapshot \\"
      echo "  --region \"${REGION}\" \\"
      echo "  --db-instance-identifier \"${RESTORE_DB_ID}\" \\"
      echo "  --db-snapshot-identifier \"${SNAPSHOT_ID}\" \\"
      echo "  --db-instance-class \"${DB_CLASS}\" \\"
      echo "  --db-subnet-group-name \"${SUBNET_GROUP}\" \\"
      echo "  --vpc-security-group-ids ${VPC_SG_IDS} \\"
      echo "  --no-publicly-accessible"
      exit 0
    fi

    aws rds restore-db-instance-from-db-snapshot \
      --region "${REGION}" \
      --db-instance-identifier "${RESTORE_DB_ID}" \
      --db-snapshot-identifier "${SNAPSHOT_ID}" \
      --db-instance-class "${DB_CLASS}" \
      --db-subnet-group-name "${SUBNET_GROUP}" \
      --vpc-security-group-ids ${VPC_SG_IDS} \
      --no-publicly-accessible

    echo "Waiting for restored DB to become available..."
    aws rds wait db-instance-available --region "${REGION}" --db-instance-identifier "${RESTORE_DB_ID}"

    aws rds describe-db-instances --region "${REGION}" \
      --db-instance-identifier "${RESTORE_DB_ID}" \
      --query "DBInstances[0].{id:DBInstanceIdentifier,endpoint:Endpoint.Address,public:PubliclyAccessible,status:DBInstanceStatus}" \
      --output table

    echo "NOTE: Update Tutor config to point to the restored endpoint if you intend to use it."
    ;;

  ebs-volume)
    SNAP_ID="${1:-}"
    AZ="${2:-}"
    if [ -z "${SNAP_ID}" ] || [ -z "${AZ}" ]; then
      usage >&2
      exit 2
    fi

    echo "Planned EBS restore:"
    echo "  Snapshot: ${SNAP_ID}"
    echo "  AZ:       ${AZ}"
    echo

    if ! confirm_or_print; then
      echo "Command to execute:"
      echo "aws ec2 create-volume \\"
      echo "  --region \"${REGION}\" \\"
      echo "  --availability-zone \"${AZ}\" \\"
      echo "  --snapshot-id \"${SNAP_ID}\" \\"
      echo "  --volume-type gp3 \\"
      echo "  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=openedx-restore-${TS}}]'"
      exit 0
    fi

    aws ec2 create-volume \
      --region "${REGION}" \
      --availability-zone "${AZ}" \
      --snapshot-id "${SNAP_ID}" \
      --volume-type gp3 \
      --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=openedx-restore-${TS}}]" \
      --query '{volumeId:VolumeId,state:State,size:Size}' \
      --output table
    ;;

  *)
    usage >&2
    exit 2
    ;;
esac
