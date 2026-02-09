#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="openedx-prod"
SECRET_NAME="openedx-tls"
DOMAINS=("lms.openedx.local" "studio.openedx.local")

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

openssl req -x509 -nodes -newkey rsa:2048 \
  -days 365 \
  -keyout "$TMP_DIR/tls.key" \
  -out "$TMP_DIR/tls.crt" \
  -subj "/CN=${DOMAINS[0]}" \
  -addext "subjectAltName=DNS:${DOMAINS[0]},DNS:${DOMAINS[1]}" >/dev/null 2>&1

kubectl -n "$NAMESPACE" create secret tls "$SECRET_NAME" \
  --cert="$TMP_DIR/tls.crt" \
  --key="$TMP_DIR/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -
