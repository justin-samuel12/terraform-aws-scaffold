# Zones, load balancers and servers are found by name and tags, never by reading another stack's state.
data "aws_route53_zone" "zones" {
  provider = aws.hub
  for_each = { for z in distinct([for f in values(local.records) : "${f.zone}|${try(f.private_zone, false)}"]) : z => z }

  name         = split("|", each.key)[0]
  private_zone = split("|", each.key)[1] == "true"
}

data "aws_lb" "load_balancers" {
  for_each = toset(compact([for f in values(local.records) : try(f.load_balancer, null)]))

  name = "${var.environment}-${each.key}"
}

data "aws_instance" "servers" {
  for_each = toset(compact([for f in values(local.records) : try(f.server, null)]))

  filter {
    name   = "tag:Name"
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

module "route53_record" {
  source = "../../modules/route53-record"

  providers = {
    aws = aws.hub
  }

  records = {
    for n, f in local.records : n => {
      zone_id = data.aws_route53_zone.zones["${f.zone}|${try(f.private_zone, false)}"].zone_id
      name    = "${try(f.name, n)}.${f.zone}"
      type    = can(f.cname) ? "CNAME" : "A"
      values  = can(f.server) ? [data.aws_instance.servers[f.server].private_ip] : can(f.cname) ? [f.cname] : []
      alias   = can(f.load_balancer) ? { name = data.aws_lb.load_balancers[f.load_balancer].dns_name, zone_id = data.aws_lb.load_balancers[f.load_balancer].zone_id } : null
    }
  }
}
