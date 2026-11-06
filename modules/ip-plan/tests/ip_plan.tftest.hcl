variables {
  config_path = "../../tests/config"
}

run "plan_is_consistent" {
  command = plan

  assert {
    condition     = length(distinct([for n in output.networks : n.cidr])) == length(output.networks)
    error_message = "Two VPCs share a CIDR."
  }

  assert {
    condition = alltrue(flatten([
      for n in output.networks : [for tier, cidrs in n.subnets : length(cidrs) == 3]
    ]))
    error_message = "Every tier needs one subnet per availability zone."
  }

  assert {
    condition     = output.networks["staging/us-west-2"].subnets.transit[0] == "10.62.252.0/28"
    error_message = "Transit subnets sit at 10.x.252.0 in every spoke VPC."
  }

  assert {
    condition     = length(distinct(flatten([for n in output.networks : flatten(values(n.subnets))]))) == length(flatten([for n in output.networks : flatten(values(n.subnets))]))
    error_message = "Two subnets share a CIDR."
  }
}

run "segments" {
  command = plan

  assert {
    condition     = output.networks["production/us-east-2"].segment == "restricted" && !contains(output.networks["production/us-east-2"].propagates_to, "standard")
    error_message = "Production must never be propagated into standard, or staging could reach it."
  }

  assert {
    condition     = output.networks["staging/us-west-2"].zones == ["usw2-az1", "usw2-az2", "usw2-az3"]
    error_message = "A network takes its region file's zone IDs."
  }

  assert {
    condition     = !contains(keys(output.networks["operations/us-east-2"].subnets), "public") && contains(keys(output.networks["staging/us-west-2"].subnets), "public")
    error_message = "Only networks with public = true get a public tier."
  }

  assert {
    condition     = output.networks["shared/us-east-2"].amazon_side_asn != output.networks["shared/us-west-2"].amazon_side_asn
    error_message = "Each hub needs its own Amazon-side ASN."
  }

  assert {
    condition     = output.primary_region == "us-east-2"
    error_message = "Ohio is the primary hub."
  }
}

run "two_zones" {
  command = plan

  variables {
    config_path = "tests/fixtures/two_zones"
  }

  assert {
    condition     = output.networks["production/us-east-2"].subnets.private == ["10.41.0.0/19", "10.41.64.0/19"]
    error_message = "Each zone takes the block numbered after it: az1 the first, az3 the third, leaving az2's free."
  }
}

run "refuses_one_zone" {
  command = plan

  variables {
    config_path = "tests/fixtures/zones"
  }

  expect_failures = [output.networks]
}

run "refuses_overlap" {
  command = plan

  variables {
    config_path = "tests/fixtures/overlap"
  }

  expect_failures = [output.networks]
}

run "refuses_typo" {
  command = plan

  variables {
    config_path = "tests/fixtures/typo"
  }

  expect_failures = [output.networks]
}

run "refuses_segment" {
  command = plan

  variables {
    config_path = "tests/fixtures/segment"
  }

  expect_failures = [output.networks]
}

run "refuses_cidr" {
  command = plan

  variables {
    config_path = "tests/fixtures/cidr"
  }

  expect_failures = [output.networks]
}

run "refuses_asn" {
  command = plan

  variables {
    config_path = "tests/fixtures/asn"
  }

  expect_failures = [output.networks]
}

run "refuses_referencing_that_is_not_a_bool" {
  command = plan

  variables {
    config_path = "tests/fixtures/referencing"
  }

  expect_failures = [output.networks]
}

run "refuses_misnamed" {
  command = plan

  variables {
    config_path = "tests/fixtures/misnamed"
  }

  expect_failures = [output.networks]
}

run "refuses_outside" {
  command = plan

  variables {
    config_path = "tests/fixtures/outside"
  }

  expect_failures = [output.networks]
}

run "refuses_primary_none" {
  command = plan

  variables {
    config_path = "tests/fixtures/primary_none"
  }

  expect_failures = [output.networks]
}

run "refuses_primary_two" {
  command = plan

  variables {
    config_path = "tests/fixtures/primary_two"
  }

  expect_failures = [output.networks]
}

run "refuses_reserved" {
  command = plan

  variables {
    config_path = "tests/fixtures/reserved"
  }

  expect_failures = [output.networks]
}

run "refuses_account" {
  command = plan

  variables {
    config_path = "tests/fixtures/account"
  }

  expect_failures = [output.networks]
}

run "refuses_misaligned" {
  command = plan

  variables {
    config_path = "tests/fixtures/misaligned"
  }

  expect_failures = [output.networks]
}

run "refuses_tiers_overlap" {
  command = plan

  variables {
    config_path = "tests/fixtures/tiers_overlap"
  }

  expect_failures = [output.networks]
}

run "refuses_too_small" {
  command = plan

  variables {
    config_path = "tests/fixtures/too_small"
  }

  expect_failures = [output.networks]
}

run "refuses_zone_seven" {
  command = plan

  variables {
    config_path = "tests/fixtures/zone_seven"
  }

  expect_failures = [output.networks]
}

run "prefix_lists_and_dns" {
  command = plan

  variables {
    config_path = "tests/fixtures/lists_and_dns"
  }

  assert {
    condition     = length(output.prefix_lists["staff-team"]) == 2 && output.prefix_lists["staff-team"][0].cidr == "10.10.70.0/24"
    error_message = "A prefix list is its entries, as written."
  }

  assert {
    condition     = output.dns.inbound && output.dns.forward["ad.example.com"] == ["10.10.128.6", "10.10.132.6"]
    error_message = "DNS forwarding sends a domain to the DNS servers of the site that answers it."
  }
}

run "sites" {
  command = plan

  variables {
    config_path = "tests/fixtures/sites"
  }

  assert {
    condition     = jsonencode(keys(output.sites)) == jsonencode(["office"]) && jsonencode(output.sites.office.ip_addresses) == jsonencode(["203.0.113.10", "203.0.113.11"]) && output.sites.office.bgp_asn == 65010
    error_message = "Each enabled site is in sites, with a VPN device per link; a site with enabled: false is left out."
  }

  assert {
    condition     = jsonencode(output.site_cidrs) == jsonencode(["10.10.0.0/16", "192.168.0.0/16"]) && jsonencode(keys(output.dns.forward)) == jsonencode(["ad.example.com"])
    error_message = "A disabled site's ranges and forwarded domains go with it."
  }
}

run "no_address_no_device" {
  command = plan

  variables {
    config_path = "tests/fixtures/lists_and_dns"
  }

  assert {
    condition     = length(output.sites.office.ip_addresses) == 0
    error_message = "A site without an ip_address has no VPN device yet."
  }
}

run "refuses_an_address_in_two_sites" {
  command = plan

  variables {
    config_path = "tests/fixtures/ip-twice"
  }

  expect_failures = [output.networks]
}

run "refuses_a_site_range_inside_a_vpc" {
  command = plan

  variables {
    config_path = "tests/fixtures/site-overlap"
  }

  expect_failures = [output.networks]
}

run "resolver_placement" {
  command = plan

  variables {
    config_path = "tests/fixtures/resolvers"
  }

  assert {
    condition     = output.networks["shared/us-east-2"].resolver.inbound && output.networks["shared/us-east-2"].resolver.outbound && !output.networks["staging/us-west-2"].resolver.inbound && output.networks["staging/us-west-2"].resolver.outbound && jsonencode(output.networks["staging/us-west-2"].resolver.domains) == jsonencode(["corp.example.com"])
    error_message = "One inbound endpoint, in the primary region; an outbound one in every region, while a site forwards anything."
  }
}

run "resolver_outbound_off_in_a_region" {
  command = plan

  variables {
    config_path = "tests/fixtures/resolver-off"
  }

  assert {
    condition     = !output.networks["staging/us-west-2"].resolver.inbound && !output.networks["staging/us-west-2"].resolver.outbound && length(output.networks["staging/us-west-2"].resolver.domains) == 0 && output.networks["operations/us-east-2"].resolver.outbound
    error_message = "hub.resolver.outbound: false leaves a region without forwarding, and only that region."
  }
}

run "refuses_resolve_all_without_a_resolver_there" {
  command = plan

  variables {
    config_path = "tests/fixtures/resolve-all-west"
  }

  expect_failures = [output.networks]
}

run "directory" {
  command = plan

  variables {
    config_path = "tests/fixtures/directory"
  }

  assert {
    condition     = output.directory.name == "ad.corp.internal" && output.directory.edition == "Standard"
    error_message = "The directory is read from config/global.yml."
  }

  assert {
    condition     = output.networks["operations/us-east-2"].resolver.outbound && contains(output.networks["operations/us-east-2"].resolver.domains, "ad.corp.internal") && !contains(output.networks["staging/us-west-2"].resolver.domains, "ad.corp.internal")
    error_message = "The directory's domain is forwarded in the primary region, where it is built, and not in the others."
  }
}

run "directory_switched_off" {
  command = plan

  variables {
    config_path = "tests/fixtures/directory-off"
  }

  assert {
    condition     = output.directory == null
    error_message = "With enabled: false nothing is built and nothing is checked, so the block can wait, blank."
  }
}

run "refuses_a_bad_directory" {
  command = plan

  variables {
    config_path = "tests/fixtures/directory-bad"
  }

  expect_failures = [output.networks]
}

run "refuses_hq" {
  command = plan

  variables {
    config_path = "tests/fixtures/hq-old"
  }

  expect_failures = [output.networks]
}

run "refuses_dns_forward" {
  command = plan

  variables {
    config_path = "tests/fixtures/forward-old"
  }

  expect_failures = [output.dns]
}

run "refuses_a_domain_forwarded_twice" {
  command = plan

  variables {
    config_path = "tests/fixtures/forward-twice"
  }

  expect_failures = [output.dns]
}

run "nothing_listed_yet" {
  command = plan

  assert {
    condition     = output.prefix_lists == {} && output.dns.forward == {} && !output.dns.inbound
    error_message = "With nothing in config, there are no lists and no DNS forwarding."
  }
}

run "each_environments_zones" {
  command = plan

  assert {
    condition     = output.zones.operations == { private = "operations.corp.internal" }
    error_message = "An environment's own zone is its private one, <environment>.<private_domain>; no public zone is ever its default."
  }

  assert {
    condition     = output.dns.public_domains == ["example.com"]
    error_message = "public_domain is a list of the public domains."
  }

  assert {
    condition     = output.dns.private_zones == toset(["corp.internal"])
    error_message = "The private domain itself is a zone in the hub that every VPC attaches to, for names every environment shares."
  }

  assert {
    condition     = !contains(keys(output.zones), "shared")
    error_message = "The hubs are not an environment with zones of their own."
  }
}

run "refuses_a_list_of_private_domains" {
  command = plan

  variables {
    config_path = "tests/fixtures/domain-list"
  }

  expect_failures = [output.dns]
}

run "refuses_one_public_domain_written_as_a_string" {
  command = plan

  variables {
    config_path = "tests/fixtures/public-string"
  }

  expect_failures = [output.dns]
}

run "refuses_dot_local" {
  command = plan

  variables {
    config_path = "tests/fixtures/dot-local"
  }

  expect_failures = [output.dns]
}

run "a_peered_network" {
  command = plan

  variables {
    config_path = "tests/fixtures/peered"
  }

  assert {
    condition     = output.networks["adhoc/us-east-2"].connectivity == "peering" && output.networks["adhoc/us-east-2"].segment == null && length(output.networks["adhoc/us-east-2"].propagates_to) == 0 && output.networks["operations/us-east-2"].connectivity == "transit_gateway"
    error_message = "A network with connectivity: peering has no segment and propagates nowhere; one without it is on the hub."
  }
}

run "refuses_a_segment_on_a_peered_network" {
  command = plan

  variables {
    config_path = "tests/fixtures/peered-with-segment"
  }

  expect_failures = [output.networks]
}
