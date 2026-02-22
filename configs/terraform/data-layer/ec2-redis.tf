resource "aws_instance" "redis" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.redis_instance_type
  subnet_id                   = length(local.private_subnet_ids) > 1 ? local.private_subnet_ids[1] : local.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.redis.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.data_layer.name

  key_name = var.ec2_ssh_key_name != "" ? var.ec2_ssh_key_name : null

  user_data = templatefile("${path.module}/../../tutor/data-layer-user-data/redis.sh", {
    redis_secret_arn = aws_secretsmanager_secret.redis.arn
    aws_region       = var.aws_region
  })

  root_block_device {
    volume_size = var.redis_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = "${local.name_prefix}-redis"
  }

  depends_on = [aws_secretsmanager_secret_version.redis]
}
