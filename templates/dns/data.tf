data "aws_default_tags" "current" {}

data "aws_vpc" "hub" {
  count = length(local.private) > 0 ? 1 : 0

  tags = {
    Environment = "shared"
    Component   = "hub"
  }
}

data "aws_vpc" "other_hubs" {
  for_each = toset([for region in local.other_hubs : region if !contains(local.foreign_hubs, region)])

  region = each.key

  tags = {
    Environment = "shared"
    Component   = "hub"
  }
}

data "aws_partition" "current" {}
