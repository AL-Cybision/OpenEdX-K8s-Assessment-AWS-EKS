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

  filter {
    name   = "tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name"
    values = [var.cluster_name]
  }
}

data "external" "worker_sg" {
  program = ["bash", "${path.module}/scripts/get-worker-sg.sh"]

  query = {
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
