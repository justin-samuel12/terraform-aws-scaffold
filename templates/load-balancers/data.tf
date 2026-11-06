data "aws_vpc" "vpc" {
  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_subnet" "subnets" {
  for_each = local.subnet_lookups

  vpc_id = data.aws_vpc.vpc.id
  tags   = { Subnet = each.key }
}

data "aws_security_group" "groups" {
  for_each = local.group_lookups

  vpc_id = data.aws_vpc.vpc.id
  tags   = { Key = each.key }
}

data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "access_logs" {
  count = length(local.load_balancers) > 0 ? 1 : 0

  bucket = "lb-logs-${data.aws_caller_identity.current.account_id}-${var.region}"
}

data "aws_acm_certificate" "certificates" {
  for_each = local.certificate_lookups

  domain      = each.key
  statuses    = ["ISSUED"]
  most_recent = true
}
