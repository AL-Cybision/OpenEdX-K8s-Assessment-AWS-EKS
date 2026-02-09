resource "aws_instance" "mongo" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.mongo_instance_type
  subnet_id                   = local.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.mongo.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.data_layer.name

  key_name = var.ec2_ssh_key_name != "" ? var.ec2_ssh_key_name : null

  user_data = templatefile("${path.module}/../../data-layer/user-data/mongo.sh", {
    mongo_secret_arn = aws_secretsmanager_secret.mongo.arn
    aws_region       = var.aws_region
    mongo_db         = var.rds_db_name
  })

  root_block_device {
    volume_size = var.mongo_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = "${local.name_prefix}-mongo"
  }

  depends_on = [aws_secretsmanager_secret_version.mongo]
}
