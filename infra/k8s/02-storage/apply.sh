#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_BIN="${TF_BIN:-${SCRIPT_DIR}/../../terraform_executable}"
if [ ! -x "${TF_BIN}" ]; then
  TF_BIN="$(command -v terraform)"
fi

MEDIA_EFS_DIR="${SCRIPT_DIR}/../../media-efs"

EFS_FS_ID="$("${TF_BIN}" -chdir="${MEDIA_EFS_DIR}" output -raw efs_file_system_id)"
EFS_AP_ID="$("${TF_BIN}" -chdir="${MEDIA_EFS_DIR}" output -raw efs_access_point_id)"

sed -e "s|__EFS_FILE_SYSTEM_ID__|${EFS_FS_ID}|g" \
    -e "s|__EFS_ACCESS_POINT_ID__|${EFS_AP_ID}|g" \
    "${SCRIPT_DIR}/openedx-media-efs.yaml" | kubectl apply -f -

kubectl -n openedx-prod wait --for=condition=Bound pvc/openedx-media --timeout=300s
kubectl -n openedx-prod get pvc openedx-media -o wide
