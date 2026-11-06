data "aws_default_tags" "current" {}

data "aws_ec2_transit_gateway" "peers" {
  for_each = toset(local.peer_regions)

  region = each.key

  filter {
    name   = "tag:Component"
    values = ["hub"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ec2_transit_gateway_route_table" "peers" {
  for_each = { for pair in setproduct(local.peer_regions, local.tables) : "${pair[0]}/${pair[1]}" => { region = pair[0], table = pair[1] } }

  region = each.value.region

  filter {
    name   = "transit-gateway-id"
    values = [data.aws_ec2_transit_gateway.peers[each.value.region].id]
  }
  filter {
    name   = "tag:Segment"
    values = [each.value.table]
  }
}
