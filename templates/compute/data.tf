data "aws_resourcegroupstaggingapi_resources" "servers" {
  count = length(local.raw_files) > 0 ? 1 : 0

  resource_type_filters = ["ec2:instance"]

  tag_filter {
    key    = "Environment"
    values = [var.environment]
  }

  tag_filter {
    key    = "Component"
    values = ["compute"]
  }
}

data "aws_vpc" "vpc" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_subnets" "tiers" {
  for_each = local.usable ? toset([for f in values(local.scaled) : try(f.tier, "private")]) : toset([])

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc[0].id]
  }

  tags = { Tier = each.key }
}

data "aws_subnet" "subnets" {
  for_each = local.usable ? toset([for s in values(local.servers) : s.subnet]) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Subnet = each.key }
}

data "aws_security_group" "groups" {
  for_each = local.usable ? local.security_group_names : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Key = each.key }
}

data "aws_iam_instance_profile" "profiles" {
  for_each = local.usable ? toset([for group, f in local.files : f.iam_instance_profile if !contains(keys(local.app_role_names), group)]) : toset([])

  name = each.key
}

data "aws_iam_policy" "shared" {
  for_each = local.usable ? local.app_role_policies : toset([])

  name = each.key
}

data "aws_kms_key" "data" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

data "aws_lb" "load_balancers" {
  for_each = local.usable ? toset(compact(concat([for r in local.routes : r.load_balancer], [for n in local.names : n.load_balancer]))) : toset([])

  name = "${var.environment}-${each.key}"
}

data "aws_lb_listener" "listeners" {
  for_each = local.usable ? toset(local.listener_keys) : toset([])

  load_balancer_arn = data.aws_lb.load_balancers[split(":", each.key)[0]].arn
  port              = tonumber(split(":", each.key)[1])
}

data "aws_lb_target_group" "targets" {
  for_each = local.usable ? toset(flatten([for t in values(local.targets) : keys(t)])) : toset([])

  arn  = startswith(each.key, "arn:") ? each.key : null
  tags = startswith(each.key, "arn:") ? null : { Key = "${var.environment}-${each.key}", Environment = var.environment }
}

data "aws_route53_zone" "zones" {
  provider = aws.dns
  for_each = local.usable ? toset([for n in local.names : "${n.zone}|${n.private}" if !n.own && !n.by_id]) : toset([])

  name         = split("|", each.key)[0]
  private_zone = split("|", each.key)[1] == "true"
}

data "aws_route53_zone" "own_zones" {
  for_each = local.usable ? toset(concat([for n in local.names : "${n.zone}|${n.private}" if n.own], length(local.server_names) > 0 ? ["${local.own_zone}|true"] : [])) : toset([])

  name         = split("|", each.key)[0]
  private_zone = split("|", each.key)[1] == "true"
}

data "aws_caller_identity" "current" {}

data "aws_ami" "images" {
  for_each = local.usable ? local.ami_names : toset([])

  owners             = [for o in local.ami_files[each.key].owners : tostring(o)]
  include_deprecated = try(tobool(local.ami_files[each.key].include_deprecated), false)

  dynamic "filter" {
    for_each = local.ami_files[each.key].filter

    content {
      name   = filter.value.name
      values = [for v in filter.value.values : tostring(v)]
    }
  }
}

data "aws_ec2_instance_type" "types" {
  for_each = local.usable ? toset(flatten(values(local.named_image_types))) : toset([])

  instance_type = each.value
}
