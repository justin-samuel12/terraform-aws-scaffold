# Group files turned into placed, addressed servers, against a mocked AWS -- docs/compute.md.
mock_provider "external" {}

mock_provider "aws" {
  alias = "hub"
}

mock_provider "aws" {
  mock_data "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::111111111111:policy/shared" }
  }
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
  target = data.aws_iam_instance_profile.profiles["accounts-service"]
  values = { name = "accounts-service" }
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

override_data {
  target = module.app_roles[0].data.aws_partition.current
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
    error_message = "One group per file, whatever it does, and one CodeDeploy role because one group's servers run an application."
  }

  assert {
    condition     = local.server_tags.grafana["CodeDeploy:grafana"] == "true" && !contains(keys(local.server_tags.grafana), "CodeDeploy") && toset(keys(module.codedeploy_application)) == toset(["grafana"])
    error_message = "The CodeDeploy tag becomes a CodeDeploy:<application> tag on the servers, and the application is built here."
  }

  assert {
    condition     = toset(module.codedeploy_application["grafana"].deployment_groups) == toset(["master", "development", "adhoc"])
    error_message = "By default, a deployment group per branch: master, development and adhoc."
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
    condition     = length(local.servers) == 0 && toset(keys(module.server_group)) == toset(["accounts-service"]) && output.autoscaling_groups["accounts-service"] == "operations-accounts-service"
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

run "applications_from_tags" {
  command = plan

  variables {
    config_dir = "tests/deployed"
  }

  assert {
    condition     = local.applications == toset(["external-api-service", "reports"]) && local.application_groups["reports"] == tolist(["api", "worker"])
    error_message = "One group can run several applications, and one application can span several groups."
  }

  assert {
    condition     = local.server_tags.api["CodeDeploy:external-api-service"] == "true" && local.server_tags.api["CodeDeploy:reports"] == "true" && local.server_tags.worker["CodeDeploy:reports"] == "true" && local.server_tags.api.Function == "api"
    error_message = "Each listed application is a tag on the group's servers; their other tags are kept. A YAML list works as well as the quoted string."
  }

  assert {
    condition     = length(local.application_selectors["reports"]) == 1 && local.application_selectors["reports"][0].key == "Function" && local.application_selectors["reports"][0].value == "api" && length(local.application_selectors["external-api-service"]) == 0
    error_message = "reports:Function=api narrows reports to servers also tagged Function = api."
  }

  assert {
    condition     = local.deployment["external-api-service"].config_name == "CodeDeployDefault.HalfAtATime" && length(local.deployment["external-api-service"].rollback_events) == 2 && local.deployment["reports"].config_name == "CodeDeployDefault.OneAtATime"
    error_message = "An application's deployments/<application>.yml overrides the defaults in config/; one without a file uses them."
  }

  assert {
    condition     = length(local.problems) == 0
    error_message = "The files are usable."
  }
}

run "refuses_the_old_codedeploy_block_and_a_stray_deployment_file" {
  command = plan

  variables {
    config_dir = "tests/undeployed"
  }

  assert {
    condition     = anytrue([for p in local.problems : startswith(p, "grafana.yml: codedeploy is now the CodeDeploy tag")]) && contains(local.problems, "deployments/nobody.yml: no group's CodeDeploy tag lists nobody")
    error_message = "The old block says where its settings went, and a deployment file for an application no server runs is named."
  }

  expect_failures = [output.servers]
}

run "blueprints" {
  command = plan

  variables {
    config_dir     = "tests/blueprinted"
    blueprints_dir = "tests/blueprints"
  }

  assert {
    condition     = toset(keys(module.server_group)) == toset(["grafana", "accounts-service", "inventory-service"]) && length(local.problems) == 0
    error_message = "Groups on a blueprint sit beside a hand-written one, and all three are usable."
  }

  assert {
    condition     = local.files["accounts-service"].count == 2 && local.files["inventory-service"].count == 1 && local.files["accounts-service"].instance_type == "t3.small" && local.files["accounts-service"].tier == "private"
    error_message = "The blueprint's settings, with the file's own count where it gives one."
  }

  assert {
    condition     = local.files["accounts-service"].target_group.health_check.path == "/accounts-service/status" && local.files["inventory-service"].target_group.health_check.path == "/inventory-service/health" && local.files["inventory-service"].target_group.port == 443
    error_message = "{app} is filled in; an allowed override changes only what it says, and the rest of the target group stays the blueprint's."
  }

  assert {
    condition     = local.files["inventory-service"].listener_rules[0].priority == 1210 && local.files["inventory-service"].listener_rules[0].path_pattern == ["/inventory-service/*"]
    error_message = "The required priority becomes the rule's, as a number; the path is the app's own."
  }

  assert {
    condition     = local.app_role_names["accounts-service"] == "operations-accounts-service-us-east-2" && local.files["accounts-service"].iam_instance_profile == "operations-accounts-service-us-east-2" && !contains(keys(local.app_role_names), "grafana")
    error_message = "Each app on the blueprint gets a role of its own, named for its environment and region; the hand-written group keeps its own."
  }

  assert {
    condition     = endswith(local.files["accounts-service"].user_data, "/blueprints/backend-service/boot.sh") && local.server_tags["accounts-service"]["CodeDeploy:accounts-service"] == "true" && contains(keys(module.codedeploy_application), "accounts-service")
    error_message = "The boot script is the blueprint's own, and the app is deployed by CodeDeploy under its name."
  }
}

run "blueprint_refusals" {
  command = plan

  variables {
    config_dir     = "tests/refused"
    blueprints_dir = "tests/blueprints"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "billing-service.yml: tier is set by blueprint backend-service/v1; an app on it may set count, instance_type, ami, target_group.health_check, target_group.stickiness, tags.Owner"),
      contains(local.problems, "billing-service.yml: instance_type m7i.24xlarge is not one blueprint backend-service/v1 offers: t3.small, t3.medium, t3.large, t3.xlarge"),
      contains(local.problems, "orders-service.yml: blueprint backend-service/v1 needs priority"),
      contains(local.problems, "claims-service.yml: blueprint backend-service/v3 not found: blueprints/backend-service/ has v1"),
    ])
    error_message = "A key the blueprint does not allow, a size it does not offer, a missing required value and a missing version are each named."
  }

  expect_failures = [output.servers]
}
