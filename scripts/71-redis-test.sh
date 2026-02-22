#!/usr/bin/env bash
set -euo pipefail

# Simple connectivity/auth smoke-test for the external Redis node.
# Usage: ./redis-test.sh <redis-host-or-ip> <redis-password>

# Read target host from arg1 and fail fast if missing.
HOST=${1:?"redis host required"}
# Read Redis password from arg2 and fail fast if missing.
PASS=${2:?"redis password required"}

# Execute an authenticated PING and print Redis response (PONG on success).
redis-cli -h "$HOST" -a "$PASS" ping
