terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "origin_domain_name" {
  description = "NGINX ingress LB DNS name"
  type        = string
}

locals {
  name_prefix = "openedx-prod"
}

resource "aws_wafv2_web_acl" "this" {
  name  = "${local.name_prefix}-cf-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "BlockHeaderXBlockMe"
    priority = 1

    action {
      block {}
    }

    statement {
      byte_match_statement {
        search_string = "1"
        field_to_match {
          single_header {
            name = "x-block-me"
          }
        }
        positional_constraint = "EXACTLY"
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "block_x_block_me"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "openedx_cf_waf"
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "OpenEdX NGINX Ingress via CloudFront"
  price_class         = "PriceClass_100"
  web_acl_id          = aws_wafv2_web_acl.this.arn
  default_root_object = ""

  origin {
    domain_name = var.origin_domain_name
    origin_id   = "nginx-ingress"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "nginx-ingress"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]

    forwarded_values {
      query_string = true
      headers      = ["Host", "Origin", "Authorization", "Accept", "Accept-Language", "User-Agent"]
      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront"
  }
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.this.arn
}
