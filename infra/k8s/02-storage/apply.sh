#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws not found in PATH" >&2; exit 1; }

MEDIA_EFS_DIR="${SCRIPT_DIR}/../../media-efs"
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Meilisearch uses an EBS-backed PVC from the default StorageClass.
# Ensure gp3 exists and is default before Tutor initializes workloads.
kubectl apply -f "${REPO_ROOT}/k8s/02-storage/storageclass-gp3.yaml"
kubectl patch storageclass gp3 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
if kubectl get storageclass gp2 >/dev/null 2>&1; then
  kubectl patch storageclass gp2 \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true
fi

if ! aws eks describe-addon \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --addon-name aws-ebs-csi-driver >/dev/null 2>&1; then
  echo "aws-ebs-csi-driver addon not found on ${CLUSTER_NAME}; run infra/eksctl/install-core-addons.sh first." >&2
  exit 1
fi

EFS_FS_ID="$(terraform -chdir="${MEDIA_EFS_DIR}" output -raw efs_file_system_id)"
EFS_AP_ID="$(terraform -chdir="${MEDIA_EFS_DIR}" output -raw efs_access_point_id)"

sed -e "s|__EFS_FILE_SYSTEM_ID__|${EFS_FS_ID}|g" \
    -e "s|__EFS_ACCESS_POINT_ID__|${EFS_AP_ID}|g" \
    "${SCRIPT_DIR}/openedx-media-efs.yaml" | kubectl apply -f -

kubectl -n openedx-prod wait --for=condition=Bound pvc/openedx-media --timeout=300s
kubectl -n openedx-prod get pvc openedx-media -o wide
