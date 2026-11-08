mock_provider "aws" {}

variables {
  config_path = "../../tests/config"
}

run "ohio_hub" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  variables {
    region = "us-east-2"
  }

  assert {
    condition     = output.network.amazon_side_asn == 64512 && output.network.cidr == "10.40.0.0/20"
    error_message = "The Ohio hub uses its own ASN and egress range from the IP plan."
  }

  assert {
    condition     = toset(keys(module.transit_gateway[0].route_table_ids)) == toset(["restricted", "standard", "shared"])
    error_message = "The hub has one route table per segment."
  }

  assert {
    condition     = toset(keys(module.vpc.subnet_ids)) == toset(["public", "transit", "dns"])
    error_message = "The egress VPC has its public and transit tiers, and a dns tier for the resolver endpoints."
  }

  assert {
    condition     = length(module.route53_resolver) == 1 && output.dns.rule_ids == {} && output.prefix_list_ids == {}
    error_message = "The resolver is ready but builds nothing, and there are no prefix lists, until config/global.yml lists them."
  }

  assert {
    condition     = length(module.vpn) == 0
    error_message = "No VPN until a site's ip_address is set in config/global.yml."
  }
}

run "oregon_hub" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["usw2-az1", "usw2-az2", "usw2-az3", "usw2-az4"] }
  }

  variables {
    region = "us-west-2"
  }

  assert {
    condition     = output.network.amazon_side_asn == 64513 && output.network.cidr == "10.60.0.0/20"
    error_message = "The Oregon hub has its own ASN and egress range."
  }
}

run "shares_with_other_accounts" {
  command = plan

  variables {
    region      = "us-east-2"
    config_path = "../../tests/stacks"
  }

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  assert {
    condition     = toset(keys(aws_ram_principal_association.network)) == toset(["444444444444"]) && contains(keys(aws_ram_resource_association.network), "transit-gateway")
    error_message = "The network is shared with every other account that has an environment in the region, and only those."
  }
}

run "private_names_for_the_command_center" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  variables {
    region      = "us-east-2"
    config_path = "../../tests/config-resolve-all"
  }

  assert {
    condition     = contains(keys(module.route53_resolver[0].rule_arns), "corp.internal") && contains(keys(local.share_resources), "resolver-rule/corp.internal")
    error_message = "With environments that resolve every private name, the hub forwards the private domain to its own inbound endpoint, and shares that rule."
  }
}

run "a_vpn_per_site" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  variables {
    region      = "us-east-2"
    config_path = "../../templates/hub/tests/sites"
  }

  assert {
    condition     = toset(keys(module.vpn)) == toset(["office/203.0.113.10", "office/203.0.113.11", "branch/198.51.100.30"])
    error_message = "One VPN per link of each enabled site: one per address, none for a site switched off, none for one whose ip_address is not known yet."
  }

  assert {
    condition     = contains(local.private_ranges, "192.168.0.0/16")
    error_message = "An enabled site's ranges outside 10.0.0.0/8 are routed through the hub."
  }
}

run "directory_in_the_primary_hub" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  override_data {
    target = module.managed_directory[0].data.aws_secretsmanager_secret_version.admin
    values = { secret_string = "not-a-real-password-1A!" }
  }

  variables {
    region      = "us-east-2"
    config_path = "../../templates/hub/tests/directory"
  }

  assert {
    condition     = length(module.managed_directory) == 1
    error_message = "With directory in config/global.yml, the primary hub builds it."
  }

  assert {
    condition     = contains(keys(module.route53_resolver[0].rule_ids), "ad.corp.internal")
    error_message = "The primary region forwards the directory's domain to its domain controllers."
  }
}

run "no_directory_in_another_hub" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["usw2-az1", "usw2-az2", "usw2-az3"] }
  }

  variables {
    region      = "us-west-2"
    config_path = "../../templates/hub/tests/directory"
  }

  assert {
    condition     = length(module.managed_directory) == 0
    error_message = "The directory is only ever in the primary hub."
  }
}

run "a_parent_runs_the_transit_gateway" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  override_data {
    target = data.aws_ec2_transit_gateway.parent[0]
    values = { id = "tgw-0123456789abcdef0" }
  }

  variables {
    region      = "us-east-2"
    config_path = "../../tests/config-parent"
  }

  assert {
    condition     = length(module.transit_gateway) == 0 && length(module.vpn) == 0 && length(module.peering) == 0
    error_message = "Where a parent organization runs the Transit Gateway, the hub builds no gateway, route tables, VPN or peering of its own."
  }

  assert {
    condition     = output.transit_gateway_id == "tgw-0123456789abcdef0" && output.route_table_ids == {}
    error_message = "The hub's VPC attaches to the parent's gateway, and leaves its route tables to the parent."
  }

  assert {
    condition     = length(aws_ram_resource_share_accepter.parent) == 1 && aws_ram_resource_share_accepter.parent[0].share_arn == "arn:aws:ram:us-east-2:999999999999:resource-share/parent-network"
    error_message = "The hub accepts the parent's share of its gateway."
  }

  assert {
    condition     = !contains(keys(local.share_resources), "transit-gateway")
    error_message = "It never shares on a gateway it does not own."
  }
}

run "peering_carries_only_what_each_segment_may_reach" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  variables {
    region = "us-east-2"
  }

  assert {
    condition     = !contains(local.reach["standard"], "restricted") && !contains(local.reach["restricted"], "standard")
    error_message = "A standard network's table holds no route to a restricted one across the peering, and the other way round."
  }

  assert {
    condition     = toset(local.reach["shared"]) == toset(local.tables)
    error_message = "Only the shared segment reaches every segment."
  }
}
