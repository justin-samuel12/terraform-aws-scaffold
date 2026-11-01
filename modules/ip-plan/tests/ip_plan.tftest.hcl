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
    condition     = !contains(keys(output.networks["development/us-east-2"].subnets), "public") && contains(keys(output.networks["staging/us-west-2"].subnets), "public")
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

  # One zone is no redundancy at all.
  variables {
    config_path = "tests/fixtures/zones"
  }

  expect_failures = [output.networks]
}

run "refuses_overlap" {
  command = plan

  # Two VPC ranges overlap.
  variables {
    config_path = "tests/fixtures/overlap"
  }

  expect_failures = [output.networks]
}

run "refuses_typo" {
  command = plan

  # A misspelt key (segmnet) is refused, not ignored.
  variables {
    config_path = "tests/fixtures/typo"
  }

  expect_failures = [output.networks]
}

run "refuses_segment" {
  command = plan

  # A segment that is not restricted, standard or shared is refused.
  variables {
    config_path = "tests/fixtures/segment"
  }

  expect_failures = [output.networks]
}

run "refuses_cidr" {
  command = plan

  # A cidr that is not a network address is refused.
  variables {
    config_path = "tests/fixtures/cidr"
  }

  expect_failures = [output.networks]
}

run "refuses_asn" {
  command = plan

  # Two hubs with the same Amazon-side ASN are refused.
  variables {
    config_path = "tests/fixtures/asn"
  }

  expect_failures = [output.networks]
}

run "refuses_misnamed" {
  command = plan

  # A file not named <environment>-<region>.yml is refused.
  variables {
    config_path = "tests/fixtures/misnamed"
  }

  expect_failures = [output.networks]
}

run "refuses_outside" {
  command = plan

  # A range outside internal_cidr is refused: the hubs would not route it.
  variables {
    config_path = "tests/fixtures/outside"
  }

  expect_failures = [output.networks]
}

run "refuses_primary_none" {
  command = plan

  # No hub says primary: true.
  variables {
    config_path = "tests/fixtures/primary_none"
  }

  expect_failures = [output.networks]
}

run "refuses_primary_two" {
  command = plan

  # Both hubs say primary: true.
  variables {
    config_path = "tests/fixtures/primary_two"
  }

  expect_failures = [output.networks]
}

run "refuses_reserved" {
  command = plan

  # shared is the hub's environment and cannot be listed under networks.
  variables {
    config_path = "tests/fixtures/reserved"
  }

  expect_failures = [output.networks]
}

run "refuses_account" {
  command = plan

  # Production with a different account in Ohio and Oregon is refused.
  variables {
    config_path = "tests/fixtures/account"
  }

  expect_failures = [output.networks]
}

run "refuses_misaligned" {
  command = plan

  # A /21 must start on a multiple of 8; start 97 is refused.
  variables {
    config_path = "tests/fixtures/misaligned"
  }

  expect_failures = [output.networks]
}

run "refuses_tiers_overlap" {
  command = plan

  # ops starting inside data is refused.
  variables {
    config_path = "tests/fixtures/tiers_overlap"
  }

  expect_failures = [output.networks]
}


run "refuses_too_small" {
  command = plan

  # A private /18 has no room for six zones in a /16.
  variables {
    config_path = "tests/fixtures/too_small"
  }

  expect_failures = [output.networks]
}

run "refuses_zone_seven" {
  command = plan

  # Zones are numbered az1 to az6; az7 has no reserved block.
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
    error_message = "DNS forwarding sends a domain to HQ's DNS servers."
  }
}

run "nothing_listed_yet" {
  command = plan

  assert {
    condition     = output.prefix_lists == {} && output.dns.forward == {} && !output.dns.inbound
    error_message = "With nothing in config, there are no lists and no DNS forwarding."
  }
}
