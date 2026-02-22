#!/usr/bin/env bash
set -euo pipefail

# Provisions external data layer (RDS MySQL + EC2 Mongo/Redis/Elasticsearch).

# Resolve script-local Terraform directory and verify tool is installed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/configs/terraform/data-layer"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws not found in PATH" >&2; exit 1; }

# Default deployment identity; override for alternate cluster/region.
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-openedx}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
NAME_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

tf_state_has() {
  terraform -chdir="${TF_DIR}" state list 2>/dev/null | rg -qx "$1"
}

tf_try_import() {
  local resource="$1"
  local import_id="$2"
  if tf_state_has "${resource}"; then
    return 0
  fi
  terraform -chdir="${TF_DIR}" import "${resource}" "${import_id}" >/dev/null
}

import_if_exists() {
  local resource="$1"
  local check_cmd="$2"
  local import_id="$3"
  if eval "${check_cmd}" >/dev/null 2>&1; then
    echo "Importing existing resource into state: ${resource}"
    tf_try_import "${resource}" "${import_id}"
  fi
}

import_secret_if_exists() {
  local resource="$1"
  local secret_name="$2"
  local secret_arn
  secret_arn="$(aws secretsmanager describe-secret --region "${AWS_REGION}" --secret-id "${secret_name}" --query 'ARN' --output text 2>/dev/null || true)"
  if [[ -n "${secret_arn}" && "${secret_arn}" != "None" ]]; then
    echo "Importing existing secret into state: ${resource}"
    tf_try_import "${resource}" "${secret_arn}"
  fi
}

import_secret_version_if_exists() {
  local resource="$1"
  local secret_name="$2"
  local secret_arn version_id
  secret_arn="$(aws secretsmanager describe-secret --region "${AWS_REGION}" --secret-id "${secret_name}" --query 'ARN' --output text 2>/dev/null || true)"
  if [[ -z "${secret_arn}" || "${secret_arn}" == "None" ]]; then
    return 0
  fi
  version_id="$(aws secretsmanager list-secret-version-ids --region "${AWS_REGION}" --secret-id "${secret_arn}" --query "Versions[?contains(VersionStages, 'AWSCURRENT')].VersionId | [0]" --output text 2>/dev/null || true)"
  if [[ -n "${version_id}" && "${version_id}" != "None" ]]; then
    echo "Importing existing secret version into state: ${resource}"
    tf_try_import "${resource}" "${secret_arn}|${version_id}"
  fi
}

import_ec2_by_name_if_exists() {
  local resource="$1"
  local tag_name="$2"
  local instance_id
  instance_id="$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters "Name=tag:Name,Values=${tag_name}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId | [0]' \
    --output text 2>/dev/null || true)"
  if [[ -n "${instance_id}" && "${instance_id}" != "None" ]]; then
    echo "Importing existing EC2 instance into state: ${resource}"
    tf_try_import "${resource}" "${instance_id}"
  fi
}

# Initialize providers/modules and local state.
terraform -chdir="${TF_DIR}" init -input=false

# Reused-account idempotency: import known singleton resources if they already exist.
import_if_exists \
  "aws_iam_role.data_layer_ec2" \
  "aws iam get-role --role-name ${NAME_PREFIX}-data-layer-ec2" \
  "${NAME_PREFIX}-data-layer-ec2"
import_if_exists \
  "aws_iam_instance_profile.data_layer" \
  "aws iam get-instance-profile --instance-profile-name ${NAME_PREFIX}-data-layer-ec2" \
  "${NAME_PREFIX}-data-layer-ec2"

SECRETS_POLICY_ARN="$(
  aws iam list-policies \
    --scope Local \
    --query "Policies[?PolicyName=='${NAME_PREFIX}-data-layer-secrets-read'].Arn | [0]" \
    --output text 2>/dev/null || true
)"
if [[ -n "${SECRETS_POLICY_ARN}" && "${SECRETS_POLICY_ARN}" != "None" ]]; then
  echo "Importing existing IAM policy into state: aws_iam_policy.secrets_read"
  tf_try_import "aws_iam_policy.secrets_read" "${SECRETS_POLICY_ARN}"
  import_if_exists \
    "aws_iam_role_policy_attachment.secrets_read" \
    "aws iam list-attached-role-policies --role-name ${NAME_PREFIX}-data-layer-ec2 --query \"AttachedPolicies[?PolicyArn=='${SECRETS_POLICY_ARN}'] | length(@)\" --output text | rg -qx '[1-9][0-9]*'" \
    "${NAME_PREFIX}-data-layer-ec2/${SECRETS_POLICY_ARN}"
fi

import_if_exists \
  "aws_iam_role_policy_attachment.ssm" \
  "aws iam list-attached-role-policies --role-name ${NAME_PREFIX}-data-layer-ec2 --query \"AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore'] | length(@)\" --output text | rg -qx '[1-9][0-9]*'" \
  "${NAME_PREFIX}-data-layer-ec2/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

import_if_exists \
  "aws_db_subnet_group.rds" \
  "aws rds describe-db-subnet-groups --region ${AWS_REGION} --db-subnet-group-name ${NAME_PREFIX}-rds" \
  "${NAME_PREFIX}-rds"
import_if_exists \
  "aws_db_parameter_group.mysql" \
  "aws rds describe-db-parameter-groups --region ${AWS_REGION} --db-parameter-group-name ${NAME_PREFIX}-mysql8-params" \
  "${NAME_PREFIX}-mysql8-params"
import_if_exists \
  "aws_db_instance.mysql" \
  "aws rds describe-db-instances --region ${AWS_REGION} --db-instance-identifier ${NAME_PREFIX}-mysql" \
  "${NAME_PREFIX}-mysql"

import_secret_if_exists "aws_secretsmanager_secret.rds" "${NAME_PREFIX}/rds-mysql"
import_secret_if_exists "aws_secretsmanager_secret.mongo" "${NAME_PREFIX}/mongo"
import_secret_if_exists "aws_secretsmanager_secret.redis" "${NAME_PREFIX}/redis"
import_secret_if_exists "aws_secretsmanager_secret.elasticsearch" "${NAME_PREFIX}/elasticsearch"
import_secret_version_if_exists "aws_secretsmanager_secret_version.rds" "${NAME_PREFIX}/rds-mysql"
import_secret_version_if_exists "aws_secretsmanager_secret_version.mongo" "${NAME_PREFIX}/mongo"
import_secret_version_if_exists "aws_secretsmanager_secret_version.redis" "${NAME_PREFIX}/redis"
import_secret_version_if_exists "aws_secretsmanager_secret_version.elasticsearch" "${NAME_PREFIX}/elasticsearch"

import_ec2_by_name_if_exists "aws_instance.mongo" "${NAME_PREFIX}-mongo"
import_ec2_by_name_if_exists "aws_instance.redis" "${NAME_PREFIX}-redis"
import_ec2_by_name_if_exists "aws_instance.elasticsearch" "${NAME_PREFIX}-elasticsearch"

if [[ "${AUTO_FIX_ENDPOINT_CIDR:-true}" == "true" ]]; then
  CLUSTER_NAME="${CLUSTER_NAME}" AWS_REGION="${AWS_REGION}" "${REPO_ROOT}/scripts/00-preflight-check.sh" >/dev/null
fi

# Build an execution plan pinned to the target cluster/region inputs.
terraform -chdir="${TF_DIR}" plan -input=false -out tfplan \
  -var "cluster_name=${CLUSTER_NAME}" \
  -var "aws_region=${AWS_REGION}"
# Apply exactly the reviewed plan file for deterministic provisioning.
terraform -chdir="${TF_DIR}" apply -input=false tfplan
