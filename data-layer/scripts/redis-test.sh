#!/usr/bin/env bash
set -euo pipefail

# Simple connectivity/auth smoke-test for the external Redis node.
# Usage: ./redis-test.sh <redis-host-or-ip> <redis-password>

HOST=${1:?"redis host required"}
PASS=${2:?"redis password required"}

redis-cli -h "$HOST" -a "$PASS" ping
