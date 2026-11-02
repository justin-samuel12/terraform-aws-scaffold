# Group files turned into placed, addressed servers, against a mocked AWS -- docs/compute.md.
mock_provider "aws" {
  alias = "hub"
}

mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { root_device_name = "/dev/xvda" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-ops-1", "subnet-ops-2", "subnet-ops-3"] }
  }
}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-operations" }
}

override_data {
  target = data.aws_security_group.groups["sqlserver"]
  values = { id = "sg-sqlserver" }
}

override_data {
  target = data.aws_kms_key.data[0]
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
}

override_data {
  target = data.aws_iam_instance_profile.profiles["sqlserver"]
  values = { name = "sqlserver" }
}

override_data {
  target = data.aws_iam_instance_profile.profiles["gitrunner"]
  values = { name = "gitrunner" }
}

override_data {
  target = data.aws_iam_instance_profile.profiles["orders-api"]
  values = { name = "orders-api" }
}

override_data {
  target = data.aws_iam_instance_profile.profiles["grafana"]
  values = { name = "grafana" }
}

override_data {
  target = data.aws_iam_instance_profile.profiles["zabbix-proxy"]
  values = { name = "zabbix-proxy" }
}

override_data {
  target = data.aws_lb_listener.listeners["internal:443"]
  values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/internal/abc/def" }
}

override_data {
  target = data.aws_lb_target_group.targets["internal-nlb/zabbix"]
  values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:targetgroup/internal-nlb-zabbix-ab12/1", name = "internal-nlb-zabbix-ab12" }
}

override_data {
  target = module.codedeploy_role[0].data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  config_path = "../../tests/config"
  environment = "operations"
  region      = "us-east-2"
}

run "placement_and_addresses" {
  command = plan

  variables {
    config_dir = "tests/groups"
  }

  assert {
    condition     = local.servers["sqlserver-01"].addresses.primary == "10.42.192.70" && local.servers["sqlserver-02"].addresses.listener == "10.42.196.72"
    error_message = "Host numbers become addresses in each server's subnet: 10.<env>.<subnet>.70."
  }

  assert {
    condition     = [for n in ["gitrunner-01", "gitrunner-02", "gitrunner-03"] : local.servers[n].subnet] == ["ops-az1", "ops-az2", "ops-az3"]
    error_message = "Unpinned servers spread across the zones in turn."
  }

  assert {
    condition     = local.servers["gitrunner-01"].addresses == {}
    error_message = "A server without ip: gets an address from AWS."
  }
}

run "refuses_an_address_outside_the_reserved_block" {
  command = plan

  variables {
    config_dir = "tests/bad-ip"
  }

  expect_failures = [output.servers]
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.servers == {}
    error_message = "Without files, no servers."
  }
}

run "refuses_a_group_without_a_role" {
  command = plan

  variables {
    config_dir = "tests/no-role"
  }

  expect_failures = [output.servers]
}

run "routed_deployed_and_behind_a_network_load_balancer" {
  command = plan

  variables {
    config_dir = "tests/routed"
  }

  assert {
    condition     = toset(keys(module.server_group)) == toset(["grafana", "zabbix-proxy"]) && length(module.codedeploy_role) == 1
    error_message = "One group per file, whatever it does, and one CodeDeploy role because one group is deployed."
  }

  assert {
    condition     = [for n in ["grafana-01", "grafana-02"] : local.servers[n].subnet] == ["ops-az1", "ops-az2"] && local.servers["zabbix-proxy-01"].subnet == "ops-az1"
    error_message = "A routed group's servers are placed like any other group's."
  }

  assert {
    condition     = local.names[0].name == "grafana.example.com" && local.names[0].load_balancer == "internal"
    error_message = "A name aliases the group's load balancer unless it says otherwise."
  }

  assert {
    condition     = local.targets["zabbix-proxy"] == { "internal-nlb/zabbix" = 10051 } && local.targets.grafana == {}
    error_message = "A group joins a network load balancer's target group by <load balancer>/<target>."
  }
}

run "refuses_two_groups_on_one_host" {
  command = plan

  variables {
    config_dir = "tests/clash"
  }

  expect_failures = [output.servers]
}

run "refuses_the_load_balancers_priorities" {
  command = plan

  variables {
    config_dir = "tests/low"
  }

  expect_failures = [output.servers]
}

run "auto_scaling_group" {
  command = plan

  variables {
    config_dir = "tests/scaled"
  }

  assert {
    condition     = length(local.servers) == 0 && toset(keys(module.server_group)) == toset(["orders-api"]) && output.autoscaling_groups["orders-api"] == "operations-orders-api"
    error_message = "A group with autoscaling is an Auto Scaling group, not named servers."
  }
}

run "refuses_autoscaling_with_count" {
  command = plan

  variables {
    config_dir = "tests/scaled-with-count"
  }

  expect_failures = [output.servers]
}

run "refuses_a_feature_key_outside_its_block" {
  command = plan

  variables {
    config_dir = "tests/flat"
  }

  expect_failures = [output.servers]
}
