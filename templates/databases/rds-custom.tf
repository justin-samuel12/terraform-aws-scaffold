resource "aws_iam_role" "rds_custom" {
  count = local.any_custom ? 1 : 0

  name                 = local.instance_prefix
  path                 = try(module.role_boundary.role_boundary.path, "/")
  permissions_boundary = try(module.role_boundary.role_boundary.permissions_boundary, null)
  description          = "RDS Custom for SQL Server servers in ${var.environment}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })

  tags = { Name = "${title(var.environment)} - ${local.instance_prefix}" }
}

resource "aws_iam_role_policy_attachment" "rds_custom" {
  count = local.any_custom ? 1 : 0

  role       = aws_iam_role.rds_custom[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonRDSCustomInstanceProfileRolePolicy"
}

resource "aws_iam_role_policy" "rds_custom" {
  count = local.any_custom ? 1 : 0

  name = "${local.instance_prefix}-data-key"
  role = aws_iam_role.rds_custom[0].name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*", "kms:DescribeKey", "kms:CreateGrant"], Resource = data.aws_kms_key.data[0].arn }]
  })
}

resource "aws_iam_instance_profile" "rds_custom" {
  count = local.any_custom ? 1 : 0

  name = local.instance_prefix
  path = try(module.role_boundary.role_boundary.path, "/")
  role = aws_iam_role.rds_custom[0].name

  tags = { Name = "${title(var.environment)} - ${local.instance_prefix}" }

  depends_on = [aws_iam_role_policy_attachment.rds_custom, aws_iam_role_policy.rds_custom]
}

module "engine_version" {
  source   = "../../modules/rds-custom-engine-version"
  for_each = local.versions_ok

  engine          = each.value.engine
  engine_version  = tostring(each.value.engine_version)
  source_image_id = each.value.source_image_id
  description     = each.value.description
}
