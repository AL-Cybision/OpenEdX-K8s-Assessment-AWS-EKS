locals {
  name_prefix         = "${var.project_name}-${var.environment}"
  vpc_id              = data.aws_eks_cluster.this.vpc_config[0].vpc_id
  private_subnet_ids  = sort(data.aws_subnets.private.ids)
  worker_sg_id        = data.external.worker_sg.result.security_group_id
  oidc_provider_url   = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  media_access_point  = "/openedx-media"
  openedx_uid         = 1000
  openedx_gid         = 1000
  openedx_media_perms = "0775"
}

