data "aws_route53_zone" "zones" {
  provider = aws.dns
  for_each = toset([for r in values(local.records) : "${r.zone_id}|${r.private}" if !r.own && !r.by_id])

  name         = split("|", each.key)[0]
  private_zone = split("|", each.key)[1] == "true"
}

data "aws_route53_zone" "own_zones" {
  for_each = toset([for r in values(local.records) : r.zone_id if r.own])

  name         = each.key
  private_zone = true
}

data "aws_lb" "load_balancers" {
  for_each = local.load_balancers

  name = "${var.environment}-${each.key}"
}

data "aws_instance" "servers" {
  for_each = local.servers

  filter {
    name   = "tag:Server"
    values = [each.key]
  }

  filter {
    name   = "tag:Environment"
    values = [var.environment]
  }

  filter {
    name   = "instance-state-name"
    values = ["running", "stopped"]
  }
}
