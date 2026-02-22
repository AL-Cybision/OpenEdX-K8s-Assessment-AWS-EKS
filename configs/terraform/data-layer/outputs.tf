output "vpc_id" {
  value = data.aws_eks_cluster.this.vpc_config[0].vpc_id
}

output "private_subnet_ids" {
  value = local.private_subnet_ids
}

output "worker_node_security_group" {
  value = local.worker_sg_id
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.address
}

output "mongo_private_ip" {
  value = aws_instance.mongo.private_ip
}

output "redis_private_ip" {
  value = aws_instance.redis.private_ip
}

output "elasticsearch_private_ip" {
  value = aws_instance.elasticsearch.private_ip
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.rds.arn
}

output "mongo_secret_arn" {
  value = aws_secretsmanager_secret.mongo.arn
}

output "redis_secret_arn" {
  value = aws_secretsmanager_secret.redis.arn
}

output "elasticsearch_secret_arn" {
  value = aws_secretsmanager_secret.elasticsearch.arn
}
