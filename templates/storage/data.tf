data "aws_vpc" "vpc" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_subnet" "subnets" {
  for_each = local.usable ? local.subnets : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Subnet = each.key }
}

data "aws_security_group" "groups" {
  for_each = local.usable ? local.groups : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Key = each.key }
}

data "aws_kms_key" "data" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}
