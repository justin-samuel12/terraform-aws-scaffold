data "aws_vpc" "vpcs" {
  for_each = toset(local.regions)

  region = each.key

  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_vpc" "hubs" {
  provider = aws.hub
  for_each = local.names.private == null ? toset([]) : toset(local.hub_regions)

  region = each.key

  tags = {
    Environment = "shared"
    Component   = "hub"
  }
}
