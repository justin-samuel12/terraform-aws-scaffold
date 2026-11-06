mock_provider "aws" {}

mock_provider "aws" {
  alias = "hub"

  mock_data "aws_ram_resource_share" {
    defaults = { arn = "arn:aws:ram:us-east-2:111111111111:resource-share/00000000-0000-0000-0000-000000000000" }
  }
}

override_data {
  target = module.vpc.data.aws_availability_zones.available
  values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
}

override_data {
  target = data.aws_ec2_transit_gateway.transit_gateway[0]
  values = { id = "tgw-ohio" }
}

override_data {
  target = data.aws_ec2_transit_gateway_route_table.route_tables["restricted"]
  values = { id = "tgw-rtb-restricted" }
}

override_data {
  target = data.aws_ec2_transit_gateway_route_table.route_tables["standard"]
  values = { id = "tgw-rtb-standard" }
}

override_data {
  target = data.aws_ec2_transit_gateway_route_table.route_tables["shared"]
  values = { id = "tgw-rtb-shared" }
}

variables {
  config_path = "../../tests/config"
}

run "operations" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
  }

  assert {
    condition     = output.network.cidr == "10.42.0.0/16" && output.network.zones == ["use2-az1", "use2-az2", "use2-az3"]
    error_message = "Operations takes its range and three Ohio zone IDs from the IP plan."
  }

  assert {
    condition     = data.aws_ec2_transit_gateway_route_table.route_tables[local.network.segment].id == "tgw-rtb-shared"
    error_message = "Operations is associated with the hub's shared route table."
  }

  assert {
    condition     = toset([for table in local.network.propagates_to : data.aws_ec2_transit_gateway_route_table.route_tables[table].id]) == toset(["tgw-rtb-restricted", "tgw-rtb-standard", "tgw-rtb-shared"])
    error_message = "Operations is reachable from every segment."
  }

  assert {
    condition     = length(aws_route53_resolver_rule_association.hub) == length(module.ip_plan.dns.forward)
    error_message = "The VPC is associated with each of the hub's forwarding rules."
  }

  assert {
    condition     = tolist(local.subnets.ops.reserved_cidrs) == tolist(["10.42.228.64/26", "10.42.230.64/26", "10.42.232.64/26"])
    error_message = "Each ops subnet reserves .64-.127 for chosen addresses."
  }

  assert {
    condition     = local.network.routes.data == "internal" && local.subnets.data.default_route == "none" && tolist(local.subnets.data.transit_routes) == tolist(["10.0.0.0/8"])
    error_message = "The data tier reaches other VPCs and HQ through the hub, and never the internet."
  }

  assert {
    condition     = output.subnets["data-az2"].cidr == "10.42.196.0/22" && output.subnets["data-az2"].zone == "use2-az2" && length(output.subnets) == 12
    error_message = "The output names each subnet as compute does: tier and zone, with its CIDR and zone ID."
  }

  assert {
    condition     = toset(keys(module.vpc.subnet_ids)) == toset(["private", "data", "ops", "transit"])
    error_message = "Operations has no public tier, so no internet gateway."
  }
}

run "production" {
  command = plan

  variables {
    environment = "production"
    region      = "us-east-2"
  }

  assert {
    condition     = data.aws_ec2_transit_gateway_route_table.route_tables[local.network.segment].id == "tgw-rtb-restricted"
    error_message = "Production is associated with the hub's restricted route table."
  }

  assert {
    condition     = !contains(local.network.propagates_to, "standard")
    error_message = "Production is never propagated into standard, so staging cannot reach it."
  }

  assert {
    condition     = toset(keys(module.vpc.subnet_ids)) == toset(["private", "data", "public", "ops", "transit"])
    error_message = "Production has a public tier for internet-facing load balancers."
  }
}

run "not_in_the_ip_plan" {
  command = plan

  variables {
    environment = "staging"
    region      = "us-east-2"
  }

  expect_failures = [var.region]
}

run "single_account" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
  }

  assert {
    condition     = length(aws_ram_resource_share_accepter.network) == 0 && length(aws_ec2_transit_gateway_vpc_attachment_accepter.network) == 0 && length(aws_ec2_transit_gateway_route_table_propagation.network) > 0
    error_message = "In the hub's own account: no share to accept, no attachment to accept, and the routing is still done."
  }
}

run "another_account" {
  command = plan

  variables {
    environment = "production"
    region      = "us-east-2"
    config_path = "../../tests/stacks"
  }

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  assert {
    condition     = local.cross_account && length(aws_ram_resource_share_accepter.network) == 1 && length(aws_ec2_transit_gateway_vpc_attachment_accepter.network) == 1
    error_message = "In another account: this account accepts the hub's share, and the hub's owner accepts the attachment before routing it."
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment_accepter.network[0].transit_gateway_default_route_table_association == false
    error_message = "The hub's owner sets the default route table settings when it accepts; the attachment leaves them to it, so plans stay quiet."
  }
}

run "only_the_command_center_resolves_every_private_name" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
    config_path = "../../tests/config-resolve-all"
  }

  assert {
    condition     = length(aws_route53_resolver_rule_association.private) == 1
    error_message = "operations, listed in resolve_all_private, attaches the hub's rule for the private domain."
  }
}

run "other_environments_do_not" {
  command = plan

  variables {
    environment = "production"
    region      = "us-east-2"
    config_path = "../../tests/config-resolve-all"
  }

  assert {
    condition     = length(aws_route53_resolver_rule_association.private) == 0
    error_message = "production is not listed, so it resolves only its own private names."
  }
}

run "peered" {
  command = plan

  variables {
    environment = "adhoc"
    region      = "us-east-2"
    config_path = "../../templates/network/tests/peering-config"
    config_dir  = "tests/adhoc"
  }

  override_data {
    target = data.aws_vpc.peers["operations"]
    values = { id = "vpc-operations" }
  }

  assert {
    condition     = local.peered && length(data.aws_ec2_transit_gateway.transit_gateway) == 0 && length(aws_ec2_transit_gateway_route_table_association.network) == 0 && length(aws_route53_resolver_rule_association.hub) == 0
    error_message = "A VPC with connectivity: peering has nothing to do with the hub."
  }

  assert {
    condition     = toset(keys(local.module_routes)) == toset(["public 0.0.0.0/0", "private 0.0.0.0/0", "private 10.42.0.0/16", "data 10.42.0.0/16"]) && local.module_routes["private 0.0.0.0/0"].nat_gateway_id == "own" && local.uses_nat
    error_message = "Its routes are the files' routes, and nothing else: the internet through its own gateways, operations through the peering."
  }

  assert {
    condition     = aws_vpc_peering_connection.peerings["operations"].peer_vpc_id == "vpc-operations" && aws_vpc_peering_connection.peerings["operations"].auto_accept && length(aws_vpc_peering_connection_accepter.peerings) == 0 && aws_vpc_peering_connection.peerings["operations"].tags.Name == "Adhoc - Peering to operations"
    error_message = "A peering in the same region and account is requested and accepted here, to the peer found by name."
  }

  assert {
    condition     = toset(keys(local.network_acls)) == toset(["data"]) && local.network_acls.data.ingress[0].protocol == "-1" && local.network_acls.data.ingress[0].rule_no == 100
    error_message = "A network ACL is written for the tier its file names, and no other."
  }
}

run "the_peer_routes_back" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
    config_path = "../../templates/network/tests/peering-config"
    config_dir  = "tests/operations-back"
  }

  assert {
    condition     = !local.peered && local.requester_cidrs["adhoc"] == "10.43.0.0/16" && toset(keys(local.module_routes)) == toset(["private 10.43.0.0/16"]) && toset(keys(data.aws_vpc_peering_connection.requested)) == toset(["adhoc"])
    error_message = "A VPC on the hub adds a route back to the environment that peered with it, finding the peering by that environment's range."
  }
}

run "refuses" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
    config_path = "../../templates/network/tests/peering-config"
    config_dir  = "tests/broken"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "route-table/attic.yml: attic is not a tier of this VPC (data, ops, private, transit)"),
      contains(local.problems, "route-table/private.yml: nat_gateway_id own is for a VPC with connectivity: peering; one on the hub goes out through the hub"),
      contains(local.problems, "route-table/private.yml: 0.0.0.0/0 is already routed for the private tier by config/global.yml"),
      contains(local.problems, "route-table/private.yml: a route takes destination_cidr_block, gateway_id, nat_gateway_id, vpc_peering_connection_id, transit_gateway_id, with destination_cidr_block and exactly one target"),
      contains(local.problems, "vpc_peering_connection_id nobody: not a file in config/peering/, a pcx- id, or an environment in config/ that peers with this one"),
      contains(local.problems, "peering/elsewhere.yml: elsewhere is in another account; peering across accounts needs that account to accept, which is not built yet"),
    ])
    error_message = "Each mistake in a route, a peering and a file's place is named."
  }

  expect_failures = [output.vpc_id]
}

run "refuses_a_file_out_of_place" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
    config_path = "../../templates/network/tests/peering-config"
    config_dir  = "tests/misplaced"
  }

  assert {
    condition     = contains(local.problems, "config/odd/thing.yml: files go in config/route-table/<tier>.yml, config/peering/<name>.yml or config/network-acl/<tier>.yml")
    error_message = "A file outside the three folders is refused."
  }

  expect_failures = [output.vpc_id]
}

run "hub_is_this_regions_transit_gateway" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
    config_path = "../../templates/network/tests/peering-config"
    config_dir  = "tests/hub-route"
  }

  assert {
    condition     = length(local.problems) == 0 && local.module_routes["data 0.0.0.0/0"].transit_gateway_id == "tgw-ohio"
    error_message = "transit_gateway_id: hub is the region's hub, found by its tags, never the word itself."
  }
}

run "refuses_a_name_that_looks_like_an_id" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
    config_path = "../../templates/network/tests/peering-config"
    config_dir  = "tests/fake-tgw"
  }

  assert {
    condition     = contains(local.problems, "route-table/data.yml: transit_gateway_id is hub, this region's hub, or a Transit Gateway id (tgw- and 17 hex digits)")
    error_message = "tgw-01 is neither the word hub nor a real id, so it is refused rather than written into the route."
  }

  expect_failures = [output.vpc_id]
}
