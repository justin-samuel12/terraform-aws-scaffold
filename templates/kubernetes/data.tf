data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_vpc" "vpc" {
  count = local.build ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_subnet" "subnets" {
  for_each = local.build ? toset([for s in local.subnets : s if !startswith(s, "subnet-")]) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Subnet = each.key }
}

data "aws_security_group" "groups" {
  for_each = local.build ? toset([for g in local.security_groups : g if !startswith(g, "sg-")]) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Key = each.key }
}

data "aws_kms_key" "data" {
  count = local.build ? 1 : 0

  key_id = "alias/${var.environment}-data"
}
