output "efs_file_system_id" {
  value = aws_efs_file_system.this.id
}

output "efs_access_point_id" {
  value = aws_efs_access_point.openedx_media.id
}

output "efs_security_group_id" {
  value = aws_security_group.efs.id
}
