resource "aws_instance" "elasticsearch" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.elasticsearch_instance_type
  subnet_id                   = local.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.elasticsearch.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.data_layer.name

  key_name = var.ec2_ssh_key_name != "" ? var.ec2_ssh_key_name : null

  user_data = templatefile("${path.module}/../../tutor/data-layer-user-data/elasticsearch.sh", {
    cluster_name = "${local.name_prefix}-es"
    node_name    = "${local.name_prefix}-es-1"
  })

  root_block_device {
    volume_size = var.elasticsearch_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name = "${local.name_prefix}-elasticsearch"
  }

  depends_on = [aws_secretsmanager_secret_version.elasticsearch]
}
