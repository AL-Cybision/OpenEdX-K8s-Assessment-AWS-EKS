data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "data_layer_ec2" {
  name               = "${local.name_prefix}-data-layer-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.data_layer_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${local.name_prefix}-data-layer-secrets-read"
  description = "Read-only access to data layer secrets"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = [
          aws_secretsmanager_secret.mongo.arn,
          aws_secretsmanager_secret.redis.arn,
          aws_secretsmanager_secret.elasticsearch.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  role       = aws_iam_role.data_layer_ec2.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

resource "aws_iam_instance_profile" "data_layer" {
  name = "${local.name_prefix}-data-layer-ec2"
  role = aws_iam_role.data_layer_ec2.name
}
