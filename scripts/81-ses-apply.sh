#!/usr/bin/env bash
set -euo pipefail

# Apply SES SMTP configuration to the in-cluster Exim relay (smtp Deployment).
# - Reads SMTP creds from AWS Secrets Manager (no secrets printed)
# - Creates/updates Kubernetes Secret
# - Patches smtp Deployment to use SMARTHOST + SMTP auth via /run/secrets/SMTP_PASSWORD
#
# Result: Open edX continues using EMAIL_HOST=smtp:8025, but Exim relays via SES on 587.

# Target region/namespace and Secrets Manager ID.
REGION="${REGION:-us-east-1}"
NAMESPACE="${NAMESPACE:-openedx-prod}"
SES_SMTP_SECRET_ID="${SES_SMTP_SECRET_ID:-openedx-prod/ses-smtp}"

# Pull SMTP auth material from Secrets Manager (do not print raw secret).
SECRET_JSON="$(aws secretsmanager get-secret-value --region "${REGION}" --secret-id "${SES_SMTP_SECRET_ID}" --query SecretString --output text | jq -c .)"
SMTP_USERNAME="$(echo "${SECRET_JSON}" | jq -r '.smtp_username')"
SMTP_PASSWORD="$(echo "${SECRET_JSON}" | jq -r '.smtp_password')"
SMARTHOST="$(echo "${SECRET_JSON}" | jq -r '.smarthost')"
FROM_EMAIL="$(echo "${SECRET_JSON}" | jq -r '.from_email // empty')"

# Some SMTP providers (including SES SMTP endpoint) expect a FQDN for HELO/EHLO.
# devture/exim-relay uses `HOSTNAME` env var for `helo_data` in the smarthost transport.
DEFAULT_HELO_HOSTNAME=""
if [[ -n "${FROM_EMAIL}" && "${FROM_EMAIL}" == *"@"* ]]; then
  DEFAULT_HELO_HOSTNAME="smtp.${FROM_EMAIL#*@}"
fi
SMTP_HELO_HOSTNAME="${SMTP_HELO_HOSTNAME:-${DEFAULT_HELO_HOSTNAME}}"

# Ensure smtp deployment exists before patching.
kubectl -n "${NAMESPACE}" get deploy smtp >/dev/null

# Export for the YAML generator (keeps secrets out of the terminal output).
export NAMESPACE SMTP_USERNAME SMTP_PASSWORD SMARTHOST FROM_EMAIL SMTP_HELO_HOSTNAME

# Create/update Kubernetes secret without printing values.
python3 - <<'PY' | kubectl -n "${NAMESPACE}" apply -f - >/dev/null
import base64
import os

ns = os.environ.get("NAMESPACE", "openedx-prod")
smtp_user = os.environ["SMTP_USERNAME"]
smtp_pass = os.environ["SMTP_PASSWORD"]
smarthost = os.environ["SMARTHOST"]

def b64(s: str) -> str:
    return base64.b64encode(s.encode("utf-8")).decode("ascii")

print(f"""apiVersion: v1
kind: Secret
metadata:
  name: ses-smtp
  namespace: {ns}
type: Opaque
data:
  SMTP_USERNAME: {b64(smtp_user)}
  SMTP_PASSWORD: {b64(smtp_pass)}
  SMARTHOST: {b64(smarthost)}
""")
PY

# Patch smtp deployment:
# - env: SMTP_USERNAME + SMARTHOST
# - volume mount: /run/secrets/SMTP_PASSWORD (file) for Exim authenticators
refresh_deploy_json() {
  # Helper to avoid repeated kubectl command duplication.
  kubectl -n "${NAMESPACE}" get deploy smtp -o json
}

DEPLOY_JSON="$(refresh_deploy_json)"
HAS_VOL="$(echo "${DEPLOY_JSON}" | jq -r '[.spec.template.spec.volumes[]?.name] | index("ses-smtp") != null')"

# VolumeMount fixup:
# If we mount a *directory* at /run/secrets, kubelet can't mount the serviceaccount at
# /var/run/secrets/... because /var/run -> /run. This manifests as CrashLoopBackOff with
# "mkdir ... /run/secrets/kubernetes.io: read-only file system".
#
# We always converge to a single-file mount:
#   /run/secrets/SMTP_PASSWORD  (subPath=SMTP_PASSWORD)

# Remove any existing ses-smtp mounts (directory or file), then re-add the correct mount.
MOUNT_INDEXES="$(echo "${DEPLOY_JSON}" | jq -r '.spec.template.spec.containers[0].volumeMounts // [] | to_entries[] | select(.value.name=="ses-smtp") | .key' | sort -nr || true)"
if [[ -n "${MOUNT_INDEXES}" ]]; then
  # Remove stale mounts first so reruns converge deterministically.
  PATCH_OPS=()
  while read -r idx; do
    [[ -z "${idx}" ]] && continue
    PATCH_OPS+=("{\"op\":\"remove\",\"path\":\"/spec/template/spec/containers/0/volumeMounts/${idx}\"}")
  done <<< "${MOUNT_INDEXES}"
  kubectl -n "${NAMESPACE}" patch deploy smtp --type='json' -p="[$(IFS=,; echo "${PATCH_OPS[*]}")]" >/dev/null
  DEPLOY_JSON="$(refresh_deploy_json)"
fi

HAS_MOUNTS_ARRAY="$(echo "${DEPLOY_JSON}" | jq -r '(.spec.template.spec.containers[0].volumeMounts|type) != "null"')"
MOUNT_OBJ='{"name":"ses-smtp","mountPath":"/run/secrets/SMTP_PASSWORD","subPath":"SMTP_PASSWORD","readOnly":true}'
if [[ "${HAS_MOUNTS_ARRAY}" == "true" ]]; then
  # Append mount if volumeMounts array already exists.
  kubectl -n "${NAMESPACE}" patch deploy smtp --type='json' -p="[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/volumeMounts/-\",\"value\":${MOUNT_OBJ}}
  ]" >/dev/null
else
  # Create volumeMounts array if absent.
  kubectl -n "${NAMESPACE}" patch deploy smtp --type='json' -p="[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/volumeMounts\",\"value\":[${MOUNT_OBJ}]}
  ]" >/dev/null
fi
DEPLOY_JSON="$(refresh_deploy_json)"

if [[ "${HAS_VOL}" != "true" ]]; then
  # Add secret-backed volume only when absent.
  HAS_ANY_VOLUMES="$(echo "${DEPLOY_JSON}" | jq -r '(.spec.template.spec.volumes|type) != "null"')"
  if [[ "${HAS_ANY_VOLUMES}" == "true" ]]; then
    kubectl -n "${NAMESPACE}" patch deploy smtp --type='json' -p='[
      {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"ses-smtp","secret":{"secretName":"ses-smtp","items":[{"key":"SMTP_PASSWORD","path":"SMTP_PASSWORD"}]}}}
    ]' >/dev/null
  else
    kubectl -n "${NAMESPACE}" patch deploy smtp --type='json' -p='[
      {"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"ses-smtp","secret":{"secretName":"ses-smtp","items":[{"key":"SMTP_PASSWORD","path":"SMTP_PASSWORD"}]}}]}
    ]' >/dev/null
  fi
fi

# Set non-secret env vars consumed by Exim relay container.
kubectl -n "${NAMESPACE}" set env deploy/smtp \
  SMTP_USERNAME="${SMTP_USERNAME}" \
  SMARTHOST="${SMARTHOST}" >/dev/null

if [[ -n "${SMTP_HELO_HOSTNAME}" ]]; then
  # Override HELO hostname when configured (improves SMTP acceptance).
  kubectl -n "${NAMESPACE}" set env deploy/smtp HOSTNAME="${SMTP_HELO_HOSTNAME}" >/dev/null
fi

# Restart so new env/volume mounts are applied to running pod.
kubectl -n "${NAMESPACE}" rollout restart deploy/smtp >/dev/null
kubectl -n "${NAMESPACE}" rollout status deploy/smtp --timeout=180s >/dev/null

echo "smtp relay now configured to use SES smarthost (no secrets printed)."
