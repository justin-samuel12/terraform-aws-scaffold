# Names, zones and chosen addresses, with no AWS at all -- docs/compute.md.
variables {
  label = "production's VPC in us-east-2"
  network = {
    zones    = ["use2-az1", "use2-az2", "use2-az3"]
    subnets  = { ops = ["10.41.228.0/23", "10.41.230.0/23", "10.41.232.0/23"], data = ["10.41.192.0/22", "10.41.196.0/22", "10.41.200.0/22"] }
    reserved = { ops = ["10.41.228.64/26", "10.41.230.64/26", "10.41.232.64/26"], data = ["10.41.192.64/26", "10.41.196.64/26", "10.41.200.64/26"] }
  }
  groups = {
    gitrunner = { count = 3, tier = "ops", instance_type = "c6i.large" }
    sqlserver = { count = 1, instance_type = "r6i.2xlarge", members = { sqlserver-01 = { subnet = "data-az2", ips = { primary = 70, listener = 72 } } } }
  }
}

run "placed" {
  command = plan

  assert {
    condition     = [for n in ["gitrunner-01", "gitrunner-02", "gitrunner-03"] : output.servers[n].subnet] == ["ops-az1", "ops-az2", "ops-az3"]
    error_message = "Servers spread across the zones in turn."
  }

  assert {
    condition     = output.servers["sqlserver-01"].addresses.listener == "10.41.196.72" && length(output.problems) == 0
    error_message = "Host numbers become addresses in the reserved block."
  }
}

run "problems_named" {
  command = plan

  variables {
    groups = {
      grafana   = { count = 1, members = { grafana-01 = { subnet = "ops-az1", ip = 31 }, grafana-09 = { subnet = "ops-az1" } } }
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
