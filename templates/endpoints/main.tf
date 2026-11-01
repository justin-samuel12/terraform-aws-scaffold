module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

# The VPC, its route tables and the tier's subnets are found by their tags, not by reading the network stack's state.
data "aws_vpc" "vpc" {
  tags = {
    Environment = var.environment
    Component   = "network"
    Name        = "vpc-01"
  }
}

data "aws_route_tables" "route_tables" {
  vpc_id = data.aws_vpc.vpc.id
}

data "aws_subnets" "tier" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = { Tier = local.settings.tier }
}

module "vpc_endpoint" {
  source = "../../modules/vpc-endpoint"

  vpc_id          = data.aws_vpc.vpc.id
  vpc_cidr        = data.aws_vpc.vpc.cidr_block
  interface       = toset(local.settings.interface)
  gateway         = toset(local.settings.gateway)
  subnet_ids      = data.aws_subnets.tier.ids
  route_table_ids = data.aws_route_tables.route_tables.ids
}
