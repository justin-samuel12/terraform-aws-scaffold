variables {
  label = "production's VPC in us-east-2"
  network = {
    zones    = ["use2-az1", "use2-az2", "use2-az3"]
    subnets  = { ops = ["10.41.228.0/23", "10.41.230.0/23", "10.41.232.0/23"], data = ["10.41.192.0/22", "10.41.196.0/22", "10.41.200.0/22"] }
    reserved = { ops = ["10.41.228.64/26", "10.41.230.64/26", "10.41.232.64/26"], data = ["10.41.192.64/26", "10.41.196.64/26", "10.41.200.64/26"] }
  }
  groups = {
    gitrunner = { count = 3, tier = "ops", instance_type = "c6i.large" }
    sqlserver = { count = 1, instance_type = "r6i.2xlarge", members = { sqlserver-01 = { subnet_id = "data-az2", private_ip = "70", secondary_private_ips = ["72"] } } }
  }
}

run "placed" {
  command = plan

  assert {
    condition     = [for n in ["gitrunner-01", "gitrunner-02", "gitrunner-03"] : output.servers[n].subnet] == ["ops-az1", "ops-az2", "ops-az3"]
    error_message = "Servers spread across the zones in turn."
  }

  assert {
    condition     = output.servers["sqlserver-01"].private_ip == "10.41.196.70" && jsonencode(output.servers["sqlserver-01"].secondary_ips) == jsonencode(["10.41.196.72"]) && length(output.problems) == 0
    error_message = "A host number becomes an address in the server's own subnet, so the same file works in every environment."
  }
}

run "problems_named" {
  command = plan

  variables {
    groups = {
      grafana   = { count = 1, members = { grafana-01 = { subnet_id = "ops-az1", private_ip = "31" }, grafana-09 = { subnet_id = "ops-az1" } } }
      sqlserver = { count = 1 }
      odd       = { count = 1, tier = "public" }
    }
  }

  assert {
    condition     = length(output.problems) == 4
    error_message = "An address outside the reserved block, an unknown member, and two missing tiers (public, and private for the unpinned server) are each named."
  }
}

run "zone_order_in_config_does_not_matter" {
  command = plan

  variables {
    network = {
      zones    = ["use2-az3", "use2-az1", "use2-az2"]
      subnets  = { ops = ["10.41.228.0/23", "10.41.230.0/23", "10.41.232.0/23"] }
      reserved = { ops = ["10.41.228.64/26", "10.41.230.64/26", "10.41.232.64/26"] }
    }
    groups = {
      runner = { count = 3, tier = "ops" }
    }
  }

  assert {
    condition     = [for n in ["runner-01", "runner-02", "runner-03"] : output.servers[n].subnet] == ["ops-az1", "ops-az2", "ops-az3"]
    error_message = "Servers spread by zone number, whatever order config lists the zones in."
  }
}

run "server_name" {
  command = plan

  variables {
    groups = {
      accounts-service = { count = 2, server_name = "accounts", tier = "ops", members = { accounts02 = { subnet_id = "ops-az3" } } }
      reports          = { count = 1, server_name = "reports", tier = "ops" }
      gitrunner        = { count = 1, tier = "ops" }
    }
  }

  assert {
    condition     = toset(keys(output.servers)) == toset(["accounts01", "accounts02", "reports01", "gitrunner-01"]) && length(output.problems) == 0
    error_message = "server_name names a group's servers, each with its number; without it they are <group>-NN."
  }

  assert {
    condition     = output.servers["accounts02"].subnet == "ops-az3" && output.servers["accounts02"].index == "02" && output.servers["accounts02"].group == "accounts-service"
    error_message = "members are keyed by those names, and each server keeps its group and number."
  }
}

run "server_name_refused" {
  command = plan

  variables {
    groups = {
      reports   = { count = 1, server_name = "gitrunner-", tier = "ops" }
      gitrunner = { count = 1, tier = "ops" }
      odd       = { count = 1, server_name = "Odd_Name", tier = "ops" }
    }
  }

  assert {
    condition = alltrue([
      contains(output.problems, "gitrunner-01: two servers would have this name; give one group another server_name"),
      contains(output.problems, "Odd_Name01: a server's name is a host name: lowercase letters, digits and hyphens, at most 63"),
    ])
    error_message = "A name two groups share, and a name no host can have, are each refused."
  }
}

run "singles_spread_across_the_zones" {
  command = plan

  variables {
    groups = { for g in ["auth", "billing", "branch", "dashboard", "ehr", "files"] : g => { count = 1, tier = "ops" } }
  }

  assert {
    condition     = [for z in ["ops-az1", "ops-az2", "ops-az3"] : length([for s in values(output.servers) : s if s.subnet == z])] == [2, 2, 2]
    error_message = "Six single servers land two to a zone, not all in the first."
  }
}

run "four_over_three_zones" {
  command = plan

  variables {
    groups = {
      api   = { count = 4, tier = "ops" }
      auth  = { count = 1, tier = "ops" }
      clinc = { count = 1, tier = "ops" }
    }
  }

  assert {
    condition     = max([for z in ["ops-az1", "ops-az2", "ops-az3"] : length([for s in values(output.servers) : s if s.group == "api" && s.subnet == z])]...) == 2
    error_message = "Four servers of one group over three zones: never more than two in one."
  }

  assert {
    condition     = [for z in ["ops-az1", "ops-az2", "ops-az3"] : length([for s in values(output.servers) : s if s.subnet == z])] == [2, 2, 2]
    error_message = "And the stack as a whole stays even."
  }
}

run "existing_servers_stay_and_new_ones_fill_the_gaps" {
  command = plan

  variables {
    groups = {
      api     = { count = 2, tier = "ops" }
      billing = { count = 1, tier = "ops" }
      branch  = { count = 1, tier = "ops" }
    }
    existing = { api-01 = "ops-az3", api-02 = "ops-az3", billing-01 = "ops-az3" }
  }

  assert {
    condition     = output.servers["api-01"].subnet == "ops-az3" && output.servers["api-02"].subnet == "ops-az3" && output.servers["billing-01"].subnet == "ops-az3"
    error_message = "Servers that exist stay in their subnet, even where a fresh placement would put them elsewhere: moving one rebuilds it."
  }

  assert {
    condition     = output.servers["branch-01"].subnet != "ops-az3"
    error_message = "A new server goes to an emptier zone."
  }
}

run "a_growing_group_goes_where_it_is_not" {
  command = plan

  variables {
    groups   = { api = { count = 3, tier = "ops" } }
    existing = { api-01 = "ops-az2" }
  }

  assert {
    condition     = output.servers["api-01"].subnet == "ops-az2" && toset([output.servers["api-02"].subnet, output.servers["api-03"].subnet]) == toset(["ops-az1", "ops-az3"])
    error_message = "A group's new servers go first to the zones where it has none."
  }
}

run "a_pin_wins_and_a_new_tier_rebuilds" {
  command = plan

  variables {
    groups = {
      api   = { count = 1, tier = "ops", members = { api-01 = { subnet_id = "ops-az1" } } }
      batch = { count = 1, tier = "ops" }
    }
    existing = { api-01 = "ops-az3", batch-01 = "data-az2" }
  }

  assert {
    condition     = output.servers["api-01"].subnet == "ops-az1" && output.servers["batch-01"].subnet != "data-az2" && startswith(output.servers["batch-01"].subnet, "ops-")
    error_message = "A pinned subnet wins over where a server is; a server in another tier than its group's is placed afresh in the group's."
  }
}

run "five_over_three_zones" {
  command = plan

  variables {
    groups = { api = { count = 5, tier = "ops" } }
  }

  assert {
    condition     = sort([for z in ["ops-az1", "ops-az2", "ops-az3"] : tostring(length([for s in values(output.servers) : s if s.subnet == z]))]) == tolist(["1", "2", "2"])
    error_message = "Five servers over three zones land 2, 2 and 1."
  }
}

run "a_lopsided_group_grows_level" {
  command = plan

  variables {
    groups   = { api = { count = 6, tier = "ops" } }
    existing = { api-01 = "ops-az1", api-02 = "ops-az1" }
  }

  assert {
    condition     = [for z in ["ops-az1", "ops-az2", "ops-az3"] : length([for s in values(output.servers) : s if s.subnet == z])] == [2, 2, 2]
    error_message = "Two servers already in one zone, growing to six: the four new ones even it out to 2, 2 and 2."
  }
}

run "a_full_address_passes_through" {
  command = plan

  variables {
    groups = {
      sqlserver = { count = 1, members = { sqlserver-01 = { subnet_id = "data-az1", private_ip = "10.41.192.70" } } }
    }
  }

  assert {
    condition     = output.servers["sqlserver-01"].private_ip == "10.41.192.70" && length(output.problems) == 0
    error_message = "A full address is kept as it is."
  }
}

run "refuses_what_is_not_an_address" {
  command = plan

  variables {
    groups = {
      sqlserver = { count = 1, members = { sqlserver-01 = { subnet_id = "data-az1", private_ip = "seventy" } } }
    }
  }

  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "seventy")
    error_message = "A value that is neither a host number nor an address is refused by name."
  }
}
