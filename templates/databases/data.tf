data "aws_vpc" "vpc" {
  count = length(local.databases) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_subnets" "data" {
  count = length(local.databases) > 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc[0].id]
  }

  tags = { Tier = "data" }
}

data "aws_security_group" "groups" {
  for_each = local.group_names

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Key = each.key }
}

data "aws_iam_role" "options" {
  for_each = local.role_names

  name = each.key
}

data "aws_kms_key" "data" {
  count = length(local.databases) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

data "aws_partition" "current" {}

data "aws_region" "current" {}
