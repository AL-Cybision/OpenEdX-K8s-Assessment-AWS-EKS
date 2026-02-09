#!/usr/bin/env bash
set -euo pipefail

HOST=${1:?"redis host required"}
PASS=${2:?"redis password required"}

redis-cli -h "$HOST" -a "$PASS" ping
