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
