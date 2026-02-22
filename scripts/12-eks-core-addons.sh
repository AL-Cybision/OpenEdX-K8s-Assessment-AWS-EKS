#!/usr/bin/env bash
set -euo pipefail

# Installs required cluster add-ons for this repo:
# - aws-ebs-csi-driver (+ IAM role), gp3 default StorageClass, metrics-server

# Resolve repository paths used by kubectl/helm applies.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default cluster identity and IAM role naming convention.
CLUSTER_NAME="${CLUSTER_NAME:-openedx-eks}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EBS_CSI_ROLE_NAME="${EBS_CSI_ROLE_NAME:-${CLUSTER_NAME}-AmazonEKS_EBS_CSI_DriverRole}"

# Hard fail early if operator prerequisites are missing.
command -v aws >/dev/null 2>&1 || { echo "aws not found in PATH" >&2; exit 1; }
command -v eksctl >/dev/null 2>&1 || { echo "eksctl not found in PATH" >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm not found in PATH" >&2; exit 1; }

echo "Ensuring OIDC provider for cluster ${CLUSTER_NAME}..."
# Required for IRSA-backed addons like EBS CSI.
eksctl utils associate-iam-oidc-provider \
  --cluster "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --approve >/dev/null

if ! aws iam get-role --role-name "${EBS_CSI_ROLE_NAME}" >/dev/null 2>&1; then
  echo "Creating IAM role for aws-ebs-csi-driver: ${EBS_CSI_ROLE_NAME}"
  # Create role only (no ServiceAccount object), then pass role ARN to addon.
  eksctl create iamserviceaccount \
    --cluster "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --role-name "${EBS_CSI_ROLE_NAME}" \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --role-only \
    --approve >/dev/null
fi

EBS_CSI_ROLE_ARN="$(aws iam get-role --role-name "${EBS_CSI_ROLE_NAME}" --query 'Role.Arn' --output text)"

# Upsert addon so script is idempotent on reruns.
if aws eks describe-addon --cluster-name "${CLUSTER_NAME}" --region "${AWS_REGION}" --addon-name aws-ebs-csi-driver >/dev/null 2>&1; then
  echo "Updating EBS CSI addon..."
  aws eks update-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "${EBS_CSI_ROLE_ARN}" \
    --resolve-conflicts OVERWRITE >/dev/null
else
  echo "Creating EBS CSI addon..."
  aws eks create-addon \
    --cluster-name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --addon-name aws-ebs-csi-driver \
    --service-account-role-arn "${EBS_CSI_ROLE_ARN}" \
    --resolve-conflicts OVERWRITE >/dev/null
fi

aws eks wait addon-active \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --addon-name aws-ebs-csi-driver

echo "Ensuring gp3 StorageClass exists and is default..."
# Make gp3 the cluster default storage class for PVCs without explicit class.
kubectl apply -f "${REPO_ROOT}/configs/k8s/storage/storageclass-gp3.yaml" >/dev/null
kubectl patch storageclass gp3 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null
if kubectl get storageclass gp2 >/dev/null 2>&1; then
  kubectl patch storageclass gp2 \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null || true
fi

echo "Installing metrics-server (required for CPU-based HPA)..."
# Prefer managed addon if available; otherwise install Helm release.
if aws eks describe-addon --cluster-name "${CLUSTER_NAME}" --region "${AWS_REGION}" --addon-name metrics-server >/dev/null 2>&1; then
  echo "metrics-server is installed as an EKS-managed addon; skipping Helm install."
else
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server >/dev/null 2>&1 || true
  helm repo update >/dev/null

  TMP_VALUES="$(mktemp)"
  trap 'rm -f "${TMP_VALUES}"' EXIT
  cat > "${TMP_VALUES}" <<'YAML'
args:
  - --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP
YAML

  if helm -n kube-system status metrics-server >/dev/null 2>&1; then
    echo "Upgrading existing Helm release: metrics-server"
    helm upgrade --install metrics-server metrics-server/metrics-server \
      --namespace kube-system \
      --values "${TMP_VALUES}" >/dev/null
  elif kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1; then
    echo "metrics-server deployment already exists and is not Helm-managed; skipping Helm install."
  else
    echo "Installing metrics-server via Helm"
    helm upgrade --install metrics-server metrics-server/metrics-server \
      --namespace kube-system \
      --values "${TMP_VALUES}" >/dev/null
  fi
fi

# Confirm deployment is healthy and resource metrics API responds.
kubectl -n kube-system rollout status deploy/metrics-server --timeout=5m

echo "Waiting for resource metrics to become available..."
for _ in $(seq 1 30); do
  if kubectl top nodes >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

kubectl top nodes >/dev/null

echo "Core add-ons ready: aws-ebs-csi-driver + metrics-server + gp3 default StorageClass."
