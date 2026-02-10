#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }

MEDIA_EFS_DIR="${SCRIPT_DIR}/../../media-efs"

EFS_FS_ID="$(terraform -chdir="${MEDIA_EFS_DIR}" output -raw efs_file_system_id)"
EFS_AP_ID="$(terraform -chdir="${MEDIA_EFS_DIR}" output -raw efs_access_point_id)"

sed -e "s|__EFS_FILE_SYSTEM_ID__|${EFS_FS_ID}|g" \
    -e "s|__EFS_ACCESS_POINT_ID__|${EFS_AP_ID}|g" \
    "${SCRIPT_DIR}/openedx-media-efs.yaml" | kubectl apply -f -

kubectl -n openedx-prod wait --for=condition=Bound pvc/openedx-media --timeout=300s
kubectl -n openedx-prod get pvc openedx-media -o wide
