#!/usr/bin/env bash
set -euo pipefail

# Resolve repo paths and ensure required CLIs are available.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
command -v terraform >/dev/null 2>&1 || { echo "terraform not found in PATH" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws not found in PATH" >&2; exit 1; }

MEDIA_EFS_DIR="${REPO_ROOT}/configs/terraform/media-efs"
# Default target cluster identity.
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Baseline EKS storage: ensure `gp3` exists and is the default StorageClass.
# (EBS CSI dynamic provisioning; some workloads may rely on a default class.)
kubectl apply -f "${REPO_ROOT}/configs/k8s/storage/storageclass-gp3.yaml"
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
  echo "aws-ebs-csi-driver addon not found on ${CLUSTER_NAME}; run scripts/12-eks-core-addons.sh first." >&2
  exit 1
fi

# Read EFS identifiers from Terraform outputs to template PV/PVC manifest.
# Init ensures providers are present on fresh clones before reading outputs.
terraform -chdir="${MEDIA_EFS_DIR}" init -input=false >/dev/null
EFS_FS_ID="$(terraform -chdir="${MEDIA_EFS_DIR}" output -raw efs_file_system_id)"
EFS_AP_ID="$(terraform -chdir="${MEDIA_EFS_DIR}" output -raw efs_access_point_id)"

sed -e "s|__EFS_FILE_SYSTEM_ID__|${EFS_FS_ID}|g" \
    -e "s|__EFS_ACCESS_POINT_ID__|${EFS_AP_ID}|g" \
    "${REPO_ROOT}/configs/k8s/storage/openedx-media-efs.yaml" | kubectl apply -f -

# Wait until claim phase becomes Bound so Tutor workloads can mount media storage.
kubectl -n openedx-prod wait --for=jsonpath='{.status.phase}'=Bound pvc/openedx-media --timeout=300s
kubectl -n openedx-prod get pvc openedx-media -o wide
