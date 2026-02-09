#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y jq awscli redis-server

SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "${redis_secret_arn}" --region "${aws_region}" --query 'SecretString' --output text)
REDIS_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

# Bind to all interfaces within private subnet; SG restricts sources
sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis/redis.conf
sed -i 's/^protected-mode .*/protected-mode yes/' /etc/redis/redis.conf

if grep -q '^# requirepass' /etc/redis/redis.conf; then
  sed -i "s/^# requirepass .*/requirepass $REDIS_PASS/" /etc/redis/redis.conf
elif grep -q '^requirepass' /etc/redis/redis.conf; then
  sed -i "s/^requirepass .*/requirepass $REDIS_PASS/" /etc/redis/redis.conf
else
  echo "requirepass $REDIS_PASS" >> /etc/redis/redis.conf
fi

systemctl enable redis-server
systemctl restart redis-server
