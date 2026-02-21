#!/usr/bin/env bash
set -euo pipefail

# EC2 user-data bootstrap for external Redis with password auth enabled.
# Terraform templates this file and replaces variables before instance launch.

# Disable interactive prompts during package install in user-data context.
export DEBIAN_FRONTEND=noninteractive

# Install required packages:
# - jq/awscli to read Secrets Manager secret
# - redis-server as data service
apt-get update -y
apt-get install -y jq awscli redis-server

# Fetch Redis application password from AWS Secrets Manager.
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "${redis_secret_arn}" --region "${aws_region}" --query 'SecretString' --output text)
REDIS_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

# Bind to all interfaces within private subnet; SG restricts sources
sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis/redis.conf
# Keep protected mode enabled (defense in depth).
sed -i 's/^protected-mode .*/protected-mode yes/' /etc/redis/redis.conf

# Ensure requirepass exists and matches secret value.
if grep -q '^# requirepass' /etc/redis/redis.conf; then
  sed -i "s/^# requirepass .*/requirepass $REDIS_PASS/" /etc/redis/redis.conf
elif grep -q '^requirepass' /etc/redis/redis.conf; then
  sed -i "s/^requirepass .*/requirepass $REDIS_PASS/" /etc/redis/redis.conf
else
  # Append requirepass if the line does not exist in this distro config.
  echo "requirepass $REDIS_PASS" >> /etc/redis/redis.conf
fi

# Enable service at boot and restart to apply new config now.
systemctl enable redis-server
systemctl restart redis-server
