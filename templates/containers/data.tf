data "aws_vpc" "vpc" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_subnet" "subnets" {
  for_each = local.usable ? toset([for s in flatten(values(local.subnet_names)) : s if !startswith(s, "subnet-")]) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Subnet = each.key }
}

data "aws_security_group" "groups" {
  for_each = local.usable ? toset([for g in flatten(values(local.group_names)) : g if !startswith(g, "sg-")]) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Key = each.key }
}

data "aws_kms_key" "data" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

data "aws_lb" "load_balancers" {
  for_each = local.usable ? toset([for r in local.routes : r.load_balancer]) : toset([])

  name = "${var.environment}-${each.key}"
}

data "aws_lb_listener" "listeners" {
  for_each = local.usable ? toset(local.listener_keys) : toset([])

  load_balancer_arn = data.aws_lb.load_balancers[split(":", each.key)[0]].arn
  port              = tonumber(split(":", each.key)[1])
}
