resource "aws_route53_zone_association" "other_regions" {
  for_each = local.names.private == null ? toset([]) : toset(slice(local.regions, 1, length(local.regions)))

  zone_id    = aws_route53_zone.private[0].zone_id
  vpc_id     = data.aws_vpc.vpcs[each.key].id
  vpc_region = each.key
}

resource "aws_route53_vpc_association_authorization" "hubs" {
  for_each = { for r in local.hub_regions : r => r if local.names.private != null && local.hub_cross[r] }

  zone_id    = aws_route53_zone.private[0].zone_id
  vpc_id     = data.aws_vpc.hubs[each.key].id
  vpc_region = each.key
}

resource "aws_route53_zone_association" "hubs_from_hub" {
  provider = aws.hub
  for_each = { for r in local.hub_regions : r => r if local.names.private != null && local.hub_cross[r] }

  zone_id    = aws_route53_zone.private[0].zone_id
  vpc_id     = data.aws_vpc.hubs[each.key].id
  vpc_region = each.key

  depends_on = [aws_route53_vpc_association_authorization.hubs]
}

resource "aws_route53_zone_association" "hubs" {
  for_each = { for r in local.hub_regions : r => r if local.names.private != null && !local.hub_cross[r] }

  zone_id    = aws_route53_zone.private[0].zone_id
  vpc_id     = data.aws_vpc.hubs[each.key].id
  vpc_region = each.key
}
