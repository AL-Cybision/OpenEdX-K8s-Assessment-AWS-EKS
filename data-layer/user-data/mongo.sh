#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y curl gnupg jq awscli

curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
cat <<'REPO' > /etc/apt/sources.list.d/mongodb-org-6.0.list
deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse
REPO

apt-get update -y
apt-get install -y mongodb-org

systemctl enable --now mongod

# Allow access only within the VPC (SG restricts sources)
if grep -q '^  bindIp:' /etc/mongod.conf; then
  sed -i 's/^  bindIp:.*/  bindIp: 0.0.0.0/' /etc/mongod.conf
else
  sed -i 's/^bindIp:.*/bindIp: 0.0.0.0/' /etc/mongod.conf || true
fi

SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "${mongo_secret_arn}" --region "${aws_region}" --query 'SecretString' --output text)
MONGO_ADMIN_USER=$(echo "$SECRET_JSON" | jq -r '.admin_username')
MONGO_ADMIN_PASS=$(echo "$SECRET_JSON" | jq -r '.admin_password')
MONGO_APP_USER=$(echo "$SECRET_JSON" | jq -r '.app_username')
MONGO_APP_PASS=$(echo "$SECRET_JSON" | jq -r '.app_password')
MONGO_DB="${mongo_db}"

mongosh --eval "db = db.getSiblingDB('admin'); if (db.getUser('$MONGO_ADMIN_USER') == null) { db.createUser({user: '$MONGO_ADMIN_USER', pwd: '$MONGO_ADMIN_PASS', roles: [{role: 'root', db: 'admin'}]}); }"
mongosh --eval "db = db.getSiblingDB('$MONGO_DB'); if (db.getUser('$MONGO_APP_USER') == null) { db.createUser({user: '$MONGO_APP_USER', pwd: '$MONGO_APP_PASS', roles: [{role: 'readWrite', db: '$MONGO_DB'}]}); }"

if ! grep -q '^security:' /etc/mongod.conf; then
  cat <<'SEC' >> /etc/mongod.conf
security:
  authorization: "enabled"
SEC
else
  if ! grep -q 'authorization' /etc/mongod.conf; then
    sed -i '/^security:/a\  authorization: "enabled"' /etc/mongod.conf
  fi
fi

systemctl restart mongod
