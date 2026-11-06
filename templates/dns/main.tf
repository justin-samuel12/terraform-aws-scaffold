module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "route53_zone" {
  source = "../../modules/route53-zone"

  public  = local.public
  private = { for zone in local.private : zone => data.aws_vpc.hub[0].id }
}

resource "aws_route53_zone_association" "other_hubs" {
  for_each = local.associations

  zone_id    = module.route53_zone.private[each.value.zone]
  vpc_id     = data.aws_vpc.other_hubs[each.value.region].id
  vpc_region = each.value.region
}

resource "aws_iam_role" "dns_writer" {
  for_each = local.writers

  name                 = "dns-${each.key}"
  description          = "${each.key} writing its own names in ${join(", ", local.domains)}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${each.value.account}:root" } }]
  })

  tags = { Name = "${local.name_prefix}dns-${each.key}" }
}

resource "aws_iam_role_policy" "dns_writer" {
  for_each = local.writers

  name = "dns-${each.key}"
  role = aws_iam_role.dns_writer[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:GetHostedZone", "route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:ListResourceRecordSets", "route53:GetChange", "route53:ListTagsForResource"]
        Resource = "*"
      },
      {
        Effect    = "Allow"
        Action    = "route53:ChangeResourceRecordSets"
        Resource  = [for d in local.domains : "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${module.route53_zone.public[d].id}"]
        Condition = { "ForAllValues:StringLike" = { "route53:ChangeResourceRecordSetsNormalizedRecordNames" = each.value.names } }
      },
    ]
  })
}
