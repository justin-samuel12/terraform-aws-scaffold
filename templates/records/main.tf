module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

locals {
  record = {
    for n, r in local.records : n => {
      zone_id = r.by_id ? r.zone_id : r.own ? data.aws_route53_zone.own_zones[r.zone_id].zone_id : data.aws_route53_zone.zones["${r.zone_id}|${r.private}"].zone_id
      name    = r.name
      type    = r.type
      ttl     = r.ttl
      records = [for v in r.records : r.type == "A" && !can(regex(local.ip, v)) ? data.aws_instance.servers[v].private_ip : v]
      alias = r.alias == null ? null : {
        name                   = strcontains(r.alias.name, ".") ? r.alias.name : data.aws_lb.load_balancers[r.alias.name].dns_name
        zone_id                = can(regex(local.zone_id, r.alias.zone_id)) ? r.alias.zone_id : data.aws_lb.load_balancers[r.alias.zone_id].zone_id
        evaluate_target_health = r.alias.evaluate_target_health
      }
    }
  }
}

module "route53_record" {
  source = "../../modules/route53-record"

  providers = {
    aws = aws.dns
  }

  records = { for n, r in local.records : n => local.record[n] if !r.own }
}

module "own_records" {
  source = "../../modules/route53-record"

  records = { for n, r in local.records : n => local.record[n] if r.own }
}
