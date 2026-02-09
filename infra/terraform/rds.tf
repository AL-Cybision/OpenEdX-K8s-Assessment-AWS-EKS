resource "aws_db_subnet_group" "rds" {
  name       = "${local.name_prefix}-rds"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-rds"
  }
}

resource "aws_db_parameter_group" "mysql" {
  name   = "${local.name_prefix}-mysql8-params"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "${local.name_prefix}-mysql8-params"
  }
}

resource "aws_db_instance" "mysql" {
  identifier              = "${local.name_prefix}-mysql"
  engine                  = "mysql"
  engine_version          = var.rds_engine_version
  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage
  db_subnet_group_name    = aws_db_subnet_group.rds.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  parameter_group_name    = aws_db_parameter_group.mysql.name
  db_name                 = var.rds_db_name
  username                = var.rds_username
  password                = random_password.rds.result
  publicly_accessible     = false
  backup_retention_period = var.rds_backup_retention_days
  multi_az                = var.rds_multi_az
  skip_final_snapshot     = var.rds_skip_final_snapshot
  final_snapshot_identifier = var.rds_skip_final_snapshot ? null : var.rds_final_snapshot_identifier

  deletion_protection = false
  storage_encrypted   = true

  tags = {
    Name = "${local.name_prefix}-mysql"
  }
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  secret_string = jsonencode({
    username = var.rds_username
    password = random_password.rds.result
    host     = aws_db_instance.mysql.address
    port     = 3306
    dbname   = var.rds_db_name
  })
}
