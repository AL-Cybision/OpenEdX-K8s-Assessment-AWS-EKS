#!/usr/bin/env bash
set -euo pipefail

# EC2 user-data bootstrap for external Elasticsearch.
# Terraform templates this file and replaces variables before instance launch.

# Disable interactive prompts in cloud-init context.
export DEBIAN_FRONTEND=noninteractive

# Install prerequisites and add Elastic apt repository.
apt-get update -y
apt-get install -y curl gnupg apt-transport-https

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic.gpg
cat <<'REPO' > /etc/apt/sources.list.d/elastic-7.x.list
deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main
REPO

apt-get update -y
apt-get install -y elasticsearch

# Required kernel tuning for Elasticsearch memory maps.
cat <<'SYSCTL' > /etc/sysctl.d/99-elasticsearch.conf
vm.max_map_count = 262144
SYSCTL
sysctl -w vm.max_map_count=262144

# Render minimal single-node Elasticsearch config for external data layer.
cat <<'ESYML' > /etc/elasticsearch/elasticsearch.yml
cluster.name: ${cluster_name}
node.name: ${node_name}
network.host: 0.0.0.0
discovery.type: single-node
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
ESYML

# Pin JVM heap for small assessment-sized instances.
mkdir -p /etc/elasticsearch/jvm.options.d
cat <<'JVM' > /etc/elasticsearch/jvm.options.d/heap.options
-Xms512m
-Xmx512m
JVM

# Ensure data/log directories exist with correct ownership.
mkdir -p /var/lib/elasticsearch /var/log/elasticsearch
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

# Reload unit files and start Elasticsearch service.
systemctl daemon-reload
systemctl enable --now elasticsearch
