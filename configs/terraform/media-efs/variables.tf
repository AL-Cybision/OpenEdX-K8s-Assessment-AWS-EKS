variable "aws_region" {
  description = "AWS region (must be us-east-1 for this assessment)"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "openedx-eks"
}

variable "project_name" {
  description = "Project name prefix for resource tagging"
  type        = string
  default     = "openedx"
}

variable "environment" {
  description = "Environment name suffix for resource tagging"
  type        = string
  default     = "prod"
}

