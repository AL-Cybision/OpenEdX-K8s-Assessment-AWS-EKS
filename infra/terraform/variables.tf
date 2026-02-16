variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name to discover VPC, subnets, and node security group"
  type        = string
  default     = "openedx-eks"
}

variable "project_name" {
  description = "Project prefix for naming"
  type        = string
  default     = "openedx"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "ec2_ssh_key_name" {
  description = "Optional EC2 key pair name for emergency SSH (leave empty to disable)"
  type        = string
  default     = ""
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS storage in GiB"
  type        = number
  default     = 20
}

variable "rds_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0.36"
}

variable "rds_backup_retention_days" {
  description = "RDS backup retention"
  type        = number
  default     = 1
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ for RDS (higher cost)"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on destroy (cost saving for non-prod)"
  type        = bool
  default     = true
}

variable "rds_final_snapshot_identifier" {
  description = "Final snapshot identifier if skip_final_snapshot is false"
  type        = string
  default     = ""
}

variable "rds_db_name" {
  description = "Initial database name"
  type        = string
  default     = "openedx"
}

variable "rds_username" {
  description = "Master username for RDS"
  type        = string
  default     = "openedx"
}

variable "mongo_instance_type" {
  description = "MongoDB EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "redis_instance_type" {
  description = "Redis EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "elasticsearch_instance_type" {
  description = "Elasticsearch EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "mongo_volume_size" {
  description = "MongoDB root volume size in GiB"
  type        = number
  default     = 20
}

variable "redis_volume_size" {
  description = "Redis root volume size in GiB"
  type        = number
  default     = 10
}

variable "elasticsearch_volume_size" {
  description = "Elasticsearch root volume size in GiB"
  type        = number
  default     = 50
}

variable "mongo_username" {
  description = "MongoDB application username"
  type        = string
  default     = "openedx"
}

variable "mongo_admin_username" {
  description = "MongoDB admin username"
  type        = string
  default     = "admin"
}

variable "redis_username" {
  description = "Redis username placeholder (Redis uses password only)"
  type        = string
  default     = ""
}

variable "elasticsearch_username" {
  description = "Elasticsearch username (if security enabled)"
  type        = string
  default     = "elastic"
}

variable "enable_s3_gateway_endpoint" {
  description = "Create S3 gateway VPC endpoint for private subnets (useful for backups without NAT)"
  type        = bool
  default     = false
}
