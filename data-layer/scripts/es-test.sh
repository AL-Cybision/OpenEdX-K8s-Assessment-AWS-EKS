#!/usr/bin/env bash
set -euo pipefail

HOST=${1:?"elasticsearch host required"}

curl -sS "http://${HOST}:9200" | head -n 1
