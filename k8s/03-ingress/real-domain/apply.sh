#!/usr/bin/env bash
set -euo pipefail

# Production-style ingress + TLS for a real domain using cert-manager + Let's Encrypt.
#
# Prereqs:
# - DNS records for LMS/CMS/MFE hosts point to the ingress-nginx LoadBalancer.
# - cert-manager is installed (see infra/cert-manager/install.sh).
#
# Usage:
#   LETSENCRYPT_EMAIL=you@example.com \
#   LMS_HOST=lms.example.com \
#   CMS_HOST=studio.example.com \
#   MFE_HOST=apps.lms.example.com \
#   ./k8s/03-ingress/real-domain/apply.sh

NAMESPACE="${NAMESPACE:-openedx-prod}"
INGRESS_CLASS="${INGRESS_CLASS:-nginx}"

: "${LETSENCRYPT_EMAIL:?Set LETSENCRYPT_EMAIL (used for ACME registration)}"
: "${LMS_HOST:?Set LMS_HOST (e.g. lms.example.com)}"
: "${CMS_HOST:?Set CMS_HOST (e.g. studio.example.com)}"
: "${MFE_HOST:?Set MFE_HOST (e.g. apps.lms.example.com)}"

ISSUER_NAME="${ISSUER_NAME:-letsencrypt-prod}"
ISSUER_PRIVATE_KEY_SECRET="${ISSUER_PRIVATE_KEY_SECRET:-${ISSUER_NAME}-account-key}"

TLS_SECRET_NAME="${TLS_SECRET_NAME:-openedx-tls-real}"
CERT_NAME="${CERT_NAME:-${TLS_SECRET_NAME}}"
INGRESS_NAME="${INGRESS_NAME:-openedx-real}"

# 1) ClusterIssuer (cluster-scoped)
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

