module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

# Private zones are created with the primary region's hub VPC, found by its tags; every other VPC associates itself.
data "aws_vpc" "hub" {
  count = length(local.private) > 0 ? 1 : 0

  tags = {
    Environment = "shared"
    Component   = "hub"
    Name        = "vpc-01"
  }
}

module "route53_zone" {
  source = "../../modules/route53-zone"

  public  = local.public
  private = { for zone in local.private : zone => data.aws_vpc.hub[0].id }
}

data "aws_vpc" "other_hubs" {
  for_each = toset([for region in local.other_hubs : region if !contains(local.foreign_hubs, region)])

  region = each.key

  tags = {
    Environment = "shared"
    Component   = "hub"
    Name        = "vpc-01"
  }
}

resource "aws_route53_zone_association" "other_hubs" {
  for_each = local.associations

  zone_id    = module.route53_zone.private[each.value.zone]
  vpc_id     = data.aws_vpc.other_hubs[each.value.region].id
  vpc_region = each.value.region
}
