# Application files turned into servers, target groups, rules, deployments and names, against a mocked AWS -- docs/compute.md.
mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-development" }
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
  target = data.aws_kms_key.data[0]
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
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
  environment = "development"
  region      = "us-east-2"
}

run "one_deployed_one_not" {
  command = plan

  variables {
    config_dir = "tests/apps"
  }

  assert {
    condition     = toset(keys(module.application)) == toset(["grafana", "zabbix-proxy"]) && length(module.codedeploy_role) == 1
    error_message = "One application per file, and one CodeDeploy role because one is deployed."
  }

  assert {
    condition     = [for n in ["grafana-01", "grafana-02"] : local.servers[n].subnet] == ["ops-az1", "ops-az2"] && local.servers["zabbix-proxy-01"].subnet == "ops-az1"
    error_message = "Each application's servers are placed like any group."
  }

  assert {
    condition     = local.names[0].name == "grafana.example.com" && local.names[0].load_balancer == "internal"
    error_message = "A name aliases the application's load balancer unless it says otherwise."
  }

  assert {
    condition     = local.targets["zabbix-proxy"] == { "internal-nlb/zabbix" = 10051 } && local.targets.grafana == {}
    error_message = "An application joins a network load balancer's target group by <load balancer>/<target>."
  }
}

run "refuses_two_applications_on_one_host" {
  command = plan

  variables {
    config_dir = "tests/clash"
  }

  expect_failures = [output.applications]
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.applications == {}
    error_message = "Without files, no applications."
  }
}

run "refuses_the_load_balancers_priorities" {
  command = plan

  variables {
    config_dir = "tests/low"
  }

  expect_failures = [output.applications]
}
