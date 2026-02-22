aws_region   = "us-east-1"
cluster_name = "openedx-eks"
project_name = "openedx"
environment  = "prod"

# Optional: set if you need SSH access via key pair
# ec2_ssh_key_name = "my-keypair"

# Production baseline sizes
rds_instance_class          = "db.t3.micro"
rds_allocated_storage       = 20
rds_backup_retention_days   = 1
rds_multi_az                = true
rds_engine_version          = "8.0.45"
mongo_instance_type         = "t3.micro"
redis_instance_type         = "t3.micro"
elasticsearch_instance_type = "t3.small"

# Enable S3 Gateway endpoint to avoid NAT dependency for backups
enable_s3_gateway_endpoint = true
