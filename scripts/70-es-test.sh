#!/usr/bin/env bash
set -euo pipefail

# Simple connectivity smoke-test for the external Elasticsearch node.
# Usage: ./es-test.sh <elasticsearch-host-or-ip>

# Read Elasticsearch host/IP from arg1 and fail fast if missing.
HOST=${1:?"elasticsearch host required"}

# Query root endpoint and print first line to confirm service is reachable.
curl -sS "http://${HOST}:9200" | head -n 1
