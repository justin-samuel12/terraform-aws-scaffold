module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

# The VPC, the tiers' subnets, the security groups and the certificates are found by name and tags, never by reading another stack's state.
data "aws_vpc" "vpc" {
  tags = {
    Environment = var.environment
    Component   = "network"
    Name        = "vpc-01"
  }
}

data "aws_subnets" "tiers" {
  for_each = local.usable_tiers

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = { Tier = each.key }
}

data "aws_security_group" "groups" {
  for_each = toset(flatten([for lb in local.load_balancers : lb.security_groups]))

  vpc_id = data.aws_vpc.vpc.id
  tags   = { Name = each.key }
}

# The region's log bucket, from the logging stack, named by account and region.
data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "access_logs" {
  count = length(local.load_balancers) > 0 ? 1 : 0

  bucket = "lb-logs-${data.aws_caller_identity.current.account_id}-${var.region}"
}

data "aws_acm_certificate" "certificates" {
  for_each = toset(compact([for lb in local.load_balancers : lb.certificate]))

  domain      = each.key
  statuses    = ["ISSUED"]
  most_recent = true
}

module "load_balancer" {
  source   = "../../modules/load-balancer"
  for_each = { for name, lb in local.load_balancers : name => lb if contains(local.usable_tiers, lb.tier) }

  name               = each.key
  type               = each.value.type
  internal           = each.value.internal
  vpc_id             = data.aws_vpc.vpc.id
  subnet_ids         = data.aws_subnets.tiers[each.value.tier].ids
  security_group_ids = [for group in each.value.security_groups : data.aws_security_group.groups[group].id]
  certificate_arn    = each.value.certificate == null ? null : data.aws_acm_certificate.certificates[each.value.certificate].arn
  access_logs_bucket = data.aws_s3_bucket.access_logs[0].id
  targets            = each.value.targets
  listeners          = each.value.listeners
  rules              = each.value.rules
}
