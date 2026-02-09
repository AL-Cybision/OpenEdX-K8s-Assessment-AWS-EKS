resource "aws_security_group" "efs" {
  name_prefix = "${local.name_prefix}-efs-"
  description = "Allow NFS from EKS worker nodes to OpenEdX media EFS"
  vpc_id      = local.vpc_id

  ingress {
    description     = "NFS from EKS workers"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [local.worker_sg_id]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-efs-sg"
  }
}

resource "aws_efs_file_system" "this" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "${local.name_prefix}-efs"
  }
}

resource "aws_efs_mount_target" "this" {
  for_each        = toset(local.private_subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "openedx_media" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = local.openedx_uid
    gid = local.openedx_gid
  }

  root_directory {
    path = local.media_access_point

    creation_info {
      owner_uid   = local.openedx_uid
      owner_gid   = local.openedx_gid
      permissions = local.openedx_media_perms
    }
  }

  tags = {
    Name = "${local.name_prefix}-efs-openedx-media"
  }

  depends_on = [aws_efs_mount_target.this]
}

