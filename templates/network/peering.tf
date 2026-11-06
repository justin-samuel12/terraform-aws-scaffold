resource "aws_vpc_peering_connection" "peerings" {
  for_each = length(local.problems) == 0 ? local.peerings : {}

  vpc_id      = module.vpc.vpc_id
  peer_vpc_id = each.value.by_name ? data.aws_vpc.peers[each.key].id : each.value.peer
  peer_region = each.value.same_region ? null : each.value.region
  auto_accept = each.value.same_region

  tags = merge(each.value.tags, { Name = "${title(var.environment)} - Peering to ${each.key}" })
}

resource "aws_vpc_peering_connection_accepter" "peerings" {
  for_each = { for name, p in local.peerings : name => p if !p.same_region && length(local.problems) == 0 }

  region                    = each.value.region
  vpc_peering_connection_id = aws_vpc_peering_connection.peerings[each.key].id
  auto_accept               = true

  tags = merge(each.value.tags, { Name = "${title(var.environment)} - Peering to ${each.key}" })
}
