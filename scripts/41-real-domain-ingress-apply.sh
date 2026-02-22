#!/usr/bin/env bash
set -euo pipefail

# Production-style ingress + TLS for a real domain using cert-manager + Let's Encrypt.
#
# Prereqs:
# - DNS records for LMS/CMS/MFE hosts point to the ingress-nginx LoadBalancer.
# - cert-manager is installed (see scripts/23-cert-manager-install.sh).
#
# Usage:
#   LETSENCRYPT_EMAIL=you@example.com \
#   LMS_HOST=lms.example.com \
#   CMS_HOST=studio.example.com \
#   MFE_HOST=apps.lms.example.com \
#   ./scripts/41-real-domain-ingress-apply.sh

NAMESPACE="${NAMESPACE:-openedx-prod}"
INGRESS_CLASS="${INGRESS_CLASS:-nginx}"

# Fail fast when mandatory host/email parameters are missing.
: "${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL (used for ACME registration)}"
: "${LMS_HOST:?Set LMS_HOST (e.g. lms.example.com)}"
: "${CMS_HOST:?Set CMS_HOST (e.g. studio.example.com)}"
: "${MFE_HOST:?Set MFE_HOST (e.g. apps.lms.example.com)}"

ISSUER_NAME="${ISSUER_NAME:-letsencrypt-prod}"
ISSUER_PRIVATE_KEY_SECRET="${ISSUER_PRIVATE_KEY_SECRET:-${ISSUER_NAME}-account-key}"

TLS_SECRET_NAME="${TLS_SECRET_NAME:-openedx-tls}"
CERT_NAME="${CERT_NAME:-${TLS_SECRET_NAME}}"
INGRESS_NAME="${INGRESS_NAME:-openedx}"

# 0) DNS pre-check
# Fail fast if hostnames are not pointing to the current ingress-nginx LB.
# This avoids waiting 15m on ACME challenges that cannot be fulfilled.
INGRESS_LB_DNS="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
if [ -z "${INGRESS_LB_DNS}" ]; then
  echo "ERROR: ingress-nginx LoadBalancer hostname is empty. Is ingress installed?" >&2
  exit 1
fi

check_host_points_to_lb() {
  local host="$1"
  local expected_lb="$2"
  local matched=0

  mapfile -t host_answers < <(dig +short "${host}" | sed 's/\.$//' | sed '/^$/d')
  mapfile -t lb_answers < <(
    {
      echo "${expected_lb}"
      dig +short "${expected_lb}"
    } | sed 's/\.$//' | sed '/^$/d' | sort -u
  )

  for ha in "${host_answers[@]:-}"; do
    for la in "${lb_answers[@]:-}"; do
      if [ "${ha}" = "${la}" ]; then
        matched=1
        break 2
      fi
    done
  done

  if [ "${matched}" -ne 1 ]; then
    echo "ERROR: DNS pre-check failed for ${host}" >&2
    echo "Expected to resolve to ingress LB: ${expected_lb}" >&2
    echo "Current answers:" >&2
    if [ "${#host_answers[@]}" -eq 0 ]; then
      echo "  (no DNS answers)" >&2
    else
      for a in "${host_answers[@]}"; do
        echo "  - ${a}" >&2
      done
    fi
    echo "Update DNS, wait for propagation, then rerun." >&2
    exit 1
  fi
}

check_host_points_to_lb "${LMS_HOST}" "${INGRESS_LB_DNS}"
check_host_points_to_lb "${CMS_HOST}" "${INGRESS_LB_DNS}"
check_host_points_to_lb "${MFE_HOST}" "${INGRESS_LB_DNS}"

echo "DNS pre-check passed: all hosts resolve to ingress LB ${INGRESS_LB_DNS}"

# 1) ClusterIssuer (cluster-scoped)
# Registers ACME account and HTTP-01 challenge solver via ingress-nginx.
kubectl apply -f - <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${ISSUER_NAME}
spec:
  acme:
    email: ${LETSENCRYPT_EMAIL}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: ${ISSUER_PRIVATE_KEY_SECRET}
    solvers:
      - http01:
          ingress:
            class: ${INGRESS_CLASS}
YAML

# 2) Certificate (namespaced) -> generates a TLS secret
# Requests a certificate covering LMS/CMS/MFE hostnames.
kubectl -n "${NAMESPACE}" apply -f - <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${CERT_NAME}
spec:
  secretName: ${TLS_SECRET_NAME}
  issuerRef:
    kind: ClusterIssuer
    name: ${ISSUER_NAME}
  dnsNames:
    - ${LMS_HOST}
    - ${CMS_HOST}
    - ${MFE_HOST}
YAML

kubectl -n "${NAMESPACE}" wait --for=condition=Ready "certificate/${CERT_NAME}" --timeout=15m

# 3) Ingress with host routing + TLS
# Applies host-based routing for LMS/CMS/MFE behind the same ingress controller.
kubectl -n "${NAMESPACE}" apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${INGRESS_NAME}
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: 100m
    nginx.ingress.kubernetes.io/limit-rps: "10"
    nginx.ingress.kubernetes.io/limit-burst: "20"
    nginx.ingress.kubernetes.io/limit-connections: "20"
spec:
  ingressClassName: ${INGRESS_CLASS}
  tls:
    - hosts:
        - ${LMS_HOST}
        - ${CMS_HOST}
        - ${MFE_HOST}
      secretName: ${TLS_SECRET_NAME}
  rules:
    - host: ${LMS_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lms
                port:
                  number: 8000
    - host: ${CMS_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: cms
                port:
                  number: 8000
    - host: ${MFE_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mfe
                port:
                  number: 8002
YAML

echo "Applied:"
echo "- ClusterIssuer/${ISSUER_NAME}"
echo "- Certificate/${CERT_NAME} (secret=${TLS_SECRET_NAME}) in namespace ${NAMESPACE}"
echo "- Ingress/${INGRESS_NAME} in namespace ${NAMESPACE}"
