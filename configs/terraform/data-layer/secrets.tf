resource "random_password" "rds" {
  length  = 24
  # Avoid characters that break RDS password rules and bootstrap scripts.
  special = false
}

resource "random_password" "mongo" {
  length  = 24
  special = false
}

resource "random_password" "mongo_admin" {
  length  = 24
  special = false
}

resource "random_password" "redis" {
  length  = 24
  special = false
}

resource "random_password" "elasticsearch" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "rds" {
  name        = "${local.name_prefix}/rds-mysql"
  description = "RDS MySQL credentials for OpenEdX"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "mongo" {
  name        = "${local.name_prefix}/mongo"
  description = "MongoDB credentials for OpenEdX"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "redis" {
  name        = "${local.name_prefix}/redis"
  description = "Redis credentials for OpenEdX"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "elasticsearch" {
  name        = "${local.name_prefix}/elasticsearch"
  description = "Elasticsearch credentials for OpenEdX (optional)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mongo" {
  secret_id = aws_secretsmanager_secret.mongo.id

  secret_string = jsonencode({
    admin_username = var.mongo_admin_username
    admin_password = random_password.mongo_admin.result
    app_username   = var.mongo_username
    app_password   = random_password.mongo.result
    dbname         = var.rds_db_name
  })

  lifecycle {
    # Avoid unintentional credential rotation when importing existing secrets.
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id

  secret_string = jsonencode({
    username = var.redis_username
    password = random_password.redis.result
  })

  lifecycle {
    # Avoid unintentional credential rotation when importing existing secrets.
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret_version" "elasticsearch" {
  secret_id = aws_secretsmanager_secret.elasticsearch.id

  secret_string = jsonencode({
    username = var.elasticsearch_username
    password = random_password.elasticsearch.result
  })

  lifecycle {
    # Avoid unintentional credential rotation when importing existing secrets.
    ignore_changes = [secret_string]
  }
}
