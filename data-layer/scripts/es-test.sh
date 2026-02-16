#!/usr/bin/env bash
set -euo pipefail

# Simple connectivity smoke-test for the external Elasticsearch node.
# Usage: ./es-test.sh <elasticsearch-host-or-ip>

HOST=${1:?"elasticsearch host required"}

curl -sS "http://${HOST}:9200" | head -n 1
