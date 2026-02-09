locals {
  name_prefix        = "${var.project_name}-${var.environment}"
  private_subnet_ids = sort(data.aws_subnets.private.ids)
  worker_sg_id       = data.external.worker_sg.result.security_group_id
}
