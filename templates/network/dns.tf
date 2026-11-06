resource "aws_route53_resolver_rule_association" "hub" {
  for_each = local.peered ? toset([]) : toset(local.network.resolver.domains)

  resolver_rule_id = data.aws_route53_resolver_rule.hub[each.key].id
  vpc_id           = module.vpc.vpc_id
}

resource "aws_route53_resolver_rule_association" "private" {
  count = local.resolves_all ? 1 : 0

  resolver_rule_id = data.aws_route53_resolver_rule.private[0].id
  vpc_id           = module.vpc.vpc_id
}

resource "aws_route53_vpc_association_authorization" "private" {
  provider = aws.hub
  for_each = local.cross_account ? module.ip_plan.dns.private_zones : toset([])

  zone_id = data.aws_route53_zone.private[each.key].zone_id
  vpc_id  = module.vpc.vpc_id
}

resource "aws_route53_zone_association" "private" {
  for_each = module.ip_plan.dns.private_zones

  zone_id = data.aws_route53_zone.private[each.key].zone_id
  vpc_id  = module.vpc.vpc_id

  depends_on = [aws_route53_vpc_association_authorization.private]
}
