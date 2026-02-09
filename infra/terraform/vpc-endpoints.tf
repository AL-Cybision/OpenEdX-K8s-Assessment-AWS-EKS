data "aws_route_table" "private" {
  for_each  = toset(local.private_subnet_ids)
  subnet_id = each.key
}

locals {
  private_route_table_ids = distinct([for rt in data.aws_route_table.private : rt.id])
}

resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_s3_gateway_endpoint ? 1 : 0
  vpc_id            = data.aws_eks_cluster.this.vpc_config[0].vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = {
    Name = "${local.name_prefix}-s3-gateway"
  }
}
