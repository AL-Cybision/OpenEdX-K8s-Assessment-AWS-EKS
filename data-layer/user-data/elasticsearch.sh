#!/usr/bin/env bash
set -euo pipefail

# EC2 user-data bootstrap for external Elasticsearch.
# Terraform templates this file and replaces ${...} variables before instance launch.

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y curl gnupg apt-transport-https

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic.gpg
cat <<'REPO' > /etc/apt/sources.list.d/elastic-7.x.list
deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main
REPO

apt-get update -y
apt-get install -y elasticsearch

cat <<'SYSCTL' > /etc/sysctl.d/99-elasticsearch.conf
vm.max_map_count = 262144
SYSCTL
sysctl -w vm.max_map_count=262144

cat <<'ESYML' > /etc/elasticsearch/elasticsearch.yml
cluster.name: ${cluster_name}
node.name: ${node_name}
network.host: 0.0.0.0
discovery.type: single-node
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
ESYML

mkdir -p /etc/elasticsearch/jvm.options.d
cat <<'JVM' > /etc/elasticsearch/jvm.options.d/heap.options
-Xms512m
-Xmx512m
JVM

mkdir -p /var/lib/elasticsearch /var/log/elasticsearch
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch

systemctl daemon-reload
systemctl enable --now elasticsearch
