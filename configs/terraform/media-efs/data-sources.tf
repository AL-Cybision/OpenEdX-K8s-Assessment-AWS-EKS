data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_eks_cluster.this.vpc_config[0].vpc_id]
  }

  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }

  # Align with eksctl tagging used in this project.
  filter {
    name   = "tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name"
    values = [var.cluster_name]
  }
}

data "external" "worker_sg" {
  # Reuse the existing discovery script. No resource names are assumed.
  program = ["bash", "${path.module}/../terraform/scripts/get-worker-sg.sh"]

  query = {
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
  }
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}
