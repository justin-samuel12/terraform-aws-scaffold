mock_provider "external" {}

mock_provider "aws" {
  alias = "dns"
}

mock_provider "aws" {
  mock_data "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::111111111111:policy/shared" }
  }
  mock_data "aws_ami" {
    defaults = { id = "ami-0aaaaaaaaaaaaaaaa", root_device_name = "/dev/xvda", architecture = "x86_64" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["x86_64"] }
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
  target = data.aws_lb_target_group.targets["internal-nlb-zabbix"]
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
  scripts_dir = "tests/scripts"
  environment = "operations"
  region      = "us-east-2"
}

run "placement_and_addresses" {
  command = plan

  variables {
    config_dir = "tests/groups"
  }

  assert {
    condition     = local.servers["sqlserver-01"].addresses[0] == "10.42.192.70" && local.servers["sqlserver-02"].addresses[2] == "10.42.196.72"
    error_message = "A server takes the addresses its file writes, primary first."
  }

  assert {
    condition     = [for n in ["gitrunner-01", "gitrunner-02", "gitrunner-03"] : local.servers[n].subnet] == ["ops-az1", "ops-az2", "ops-az3"]
    error_message = "Unpinned servers spread across the zones in turn."
  }

  assert {
    condition     = length(local.servers["gitrunner-01"].addresses) == 0
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
    condition     = [for n in ["grafana-01", "grafana-02"] : local.servers[n].subnet] == ["ops-az1", "ops-az2"] && local.servers["zabbix-proxy-01"].subnet == "ops-az3"
    error_message = "A routed group's servers are placed like any other group's, and the next group's server goes to the zone left empty."
  }

  assert {
    condition     = local.names[0].name == "grafana.example.com" && local.names[0].load_balancer == "internal"
    error_message = "A record's full name, aliased to the load balancer it names."
  }

  assert {
    condition     = local.targets["zabbix-proxy"] == { "internal-nlb-zabbix" = 10051 } && local.targets.grafana == {}
    error_message = "A group joins a network load balancer's target group by its name, <load balancer>-<target>, on the port it gives."
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
    error_message = "A group with autoscaling_group is an Auto Scaling group, not named servers."
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
    condition     = one([for r in local.routes : r if r.group == "inventory-service"]).priority == 1210 && jsonencode(one([for r in local.routes : r if r.group == "inventory-service"]).paths) == jsonencode(["/inventory-service/*"])
    error_message = "The required priority becomes the rule's, as a number; the path is the app's own."
  }

  assert {
    condition     = local.app_role_names["accounts-service"] == "operations-accounts-service-us-east-2" && local.files["accounts-service"].iam_instance_profile == "operations-accounts-service-us-east-2" && !contains(keys(local.app_role_names), "grafana")
    error_message = "Each app on the blueprint gets a role of its own, named for its environment and region; the hand-written group keeps its own."
  }

  assert {
    condition     = local.files["accounts-service"].user_data == "scripts/boot.sh" && endswith(local.user_data_paths["accounts-service"], "tests/scripts/boot.sh") && local.server_tags["accounts-service"]["CodeDeploy:accounts-service"] == "true" && contains(keys(module.codedeploy_application), "accounts-service")
    error_message = "The boot script is read from the scripts folder, and the app is deployed by CodeDeploy under its name."
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
      contains(local.problems, "orders-service.yml: blueprint backend-service/v1 needs listener_rule"),
      contains(local.problems, "crowded.yml: vpc_security_group_ids lists 6; a server takes at most 5"),
      contains(local.problems, "named.yml: the tag Name is the stack's own (Name is the server's, <group>-01); give yours another name"),
      contains(local.problems, "claims-service.yml: blueprint backend-service/v3 not found: blueprints/compute/backend-service/ has v1"),
    ])
    error_message = "A key the blueprint does not allow, a size it does not offer, a missing required value and a missing version are each named."
  }

  expect_failures = [output.servers]
}

run "the_blueprints" {
  command = plan

  variables {
    config_dir     = "tests/on-blueprints"
    blueprints_dir = "../../blueprints/compute"
    scripts_dir    = "../../scripts"
  }

  override_data {
    target = data.aws_lb_listener.listeners["public:443"]
    values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/public/abc/def" }
  }

  override_data {
    target = data.aws_lb_listener.listeners["staff:443"]
    values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/staff/abc/def" }
  }

  override_data {
    target = data.aws_lb_listener.listeners["services:443"]
    values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/services/abc/def" }
  }

  override_data {
    target = module.codedeploy_application["grafana"].data.external.ownership[0]
    values = { result = { exists = "false", owner = "" } }
  }

  assert {
    condition     = length(local.problems) == 0 && toset(keys(module.server_group)) == toset(["sso", "admin-portal", "grafana", "accounts-service"])
    error_message = "One app on each blueprint, all usable."
  }

  assert {
    condition     = one([for r in local.routes : r if r.group == "sso"]).load_balancer == "public" && one([for r in local.routes : r if r.group == "sso"]).listener == "443" && jsonencode(one([for r in local.routes : r if r.group == "sso"]).hosts) == jsonencode(["sso.example.com", "login.example.com"]) && one([for r in local.routes : r if r.group == "sso"]).priority == 1100 && jsonencode(local.files["sso"].vpc_security_group_ids) == jsonencode(["frontends", "services-lb-clients", "sqlserver-clients", "monitoring-agent"])
    error_message = "A frontend answers its own host names on the public load balancer, in its own group plus the client and agent groups every app carries."
  }

  assert {
    condition     = one([for r in local.routes : r if r.group == "admin-portal"]).load_balancer == "staff" && jsonencode(one([for r in local.routes : r if r.group == "admin-portal"]).hosts) == jsonencode(["admin-portal.example.com"]) && local.files["admin-portal"].count == 1 && jsonencode(local.files["admin-portal"].vpc_security_group_ids) == jsonencode(["staff-apps", "services-lb-clients", "sqlserver-clients", "monitoring-agent"])
    error_message = "A staff app is on the staff load balancer, in the staff-apps group."
  }

  assert {
    condition     = local.containerized["grafana"] && !local.containerized["sso"] && one([for r in local.routes : r if r.group == "grafana"]).load_balancer == "staff" && local.files["grafana"].target_group.health_check.path == "/api/health" && local.files["grafana"].root_block_device.volume_size == 75
    error_message = "A container app is containerized for CodeDeploy, on the staff load balancer, with its own health check and room for images."
  }

  assert {
    condition     = one([for r in local.routes : r if r.group == "accounts-service"]).load_balancer == "services" && jsonencode(one([for r in local.routes : r if r.group == "accounts-service"]).paths) == jsonencode(["/accounts-service/*", "/accountss/*"]) && one([for r in local.routes : r if r.group == "accounts-service"]).priority == 1200
    error_message = "A backend service is reached by path on the services load balancer: its own paths, the blueprint's load balancer, its priority."
  }

  assert {
    condition     = jsonencode(local.files["accounts-service"].vpc_security_group_ids) == jsonencode(["backend-services", "services-lb-clients", "sqlserver-clients", "monitoring-agent", "accounts-files"]) && jsonencode(local.files["sso"].vpc_security_group_ids) == jsonencode(["frontends", "services-lb-clients", "sqlserver-clients", "monitoring-agent"]) && local.files["accounts-service"].target_group.health_check.path == "/accounts-service/health" && local.files["accounts-service"].target_group.health_check.matcher == "200"
    error_message = "Its own group is added to the blueprint's; its own health check path keeps the blueprint's matcher."
  }

  assert {
    condition     = local.app_role_names["grafana"] == "operations-grafana-us-east-2" && local.app_role_names["sso"] == "operations-sso-us-east-2"
    error_message = "Every app on a blueprint gets a role of its own."
  }

  assert {
    condition     = endswith(local.user_data_paths["sso"], "/scripts/ubuntu.sh") && local.user_data_paths["admin-portal"] == local.user_data_paths["accounts-service"] && local.user_data_paths["sso"] == local.user_data_paths["accounts-service"]
    error_message = "Every blueprint without Docker boots from the one shared script, scripts/ubuntu.sh."
  }

  assert {
    condition     = endswith(local.user_data_paths["grafana"], "/scripts/ubuntu-container.sh") && !strcontains(file(local.user_data_paths["sso"]), "docker") && replace(file(local.user_data_paths["grafana"]), "for unit in docker ", "for unit in ") == file(local.user_data_paths["sso"])
    error_message = "Only container-app servers start Docker, and their script differs from scripts/ubuntu.sh in nothing else."
  }

  assert {
    condition     = local.member_tags["accounts-service-01"] == { DNS = "accounts01", Slot = "01" } && local.member_tags["accounts-service-02"] == { DNS = "accounts-legacy", Slot = "02" }
    error_message = "A server's own tags are its own."
  }

  assert {
    condition     = contains(keys(module.server_group["grafana"].servers), "grafana01") && local.member_tags["grafana01"] == { DNS = "grafana01" } && local.member_tags["sso-01"] == { DNS = "sso-01" }
    error_message = "server_name names the servers, and the blueprint's DNS follows the server's name, whichever it is."
  }

  assert {
    condition     = local.group_tags["accounts-service"].BackupTier == "Daily" && !contains(keys(local.group_tags["accounts-service"]), "Slot") && !contains(keys(local.group_tags["accounts-service"]), "DNS")
    error_message = "Tags that name one server go on each server, never on the group with the placeholder still in them."
  }

  assert {
    condition     = aws_route53_record.servers["accounts-service-01"].name == "accounts01.operations.corp.internal" && aws_route53_record.servers["accounts-service-02"].name == "accounts-legacy.operations.corp.internal" && aws_route53_record.servers["grafana01"].type == "A"
    error_message = "A server's DNS tag is its name in the environment's own private zone: an A record to its address, with nothing else to write."
  }

  assert {
    condition     = local.server_names["sso-01"] == "sso-01.operations.corp.internal"
    error_message = "The stack shows each server's internal name."
  }
}

run "existing_servers_stay_put" {
  command = plan

  variables {
    config_dir     = "tests/on-blueprints"
    blueprints_dir = "../../blueprints/compute"
    scripts_dir    = "../../scripts"
  }

  override_data {
    target = data.aws_lb_listener.listeners["public:443"]
    values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/public/abc/def" }
  }

  override_data {
    target = data.aws_lb_listener.listeners["staff:443"]
    values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/staff/abc/def" }
  }

  override_data {
    target = data.aws_lb_listener.listeners["services:443"]
    values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/services/abc/def" }
  }

  override_data {
    target = module.codedeploy_application["grafana"].data.external.ownership[0]
    values = { result = { exists = "false", owner = "" } }
  }

  override_data {
    target = data.aws_resourcegroupstaggingapi_resources.servers[0]
    values = {
      resource_tag_mapping_list = [
        { resource_arn = "arn:aws:ec2:us-east-2:111111111111:instance/i-1", compliance_details = [], tags = { Name = "Production - grafana01", Server = "grafana01", Subnet = "private-az3" } },
        { resource_arn = "arn:aws:ec2:us-east-2:111111111111:instance/i-2", compliance_details = [], tags = { Name = "accounts-service-01", Subnet = "private-az3" } },
      ]
    }
  }

  assert {
    condition     = local.existing == { grafana01 = "private-az3", accounts-service-01 = "private-az3" } && local.servers["grafana01"].subnet == "private-az3" && local.servers["accounts-service-01"].subnet == "private-az3"
    error_message = "Servers the tagging API says exist stay in their subnets, found by their Server tag, or by Name for one built before it."
  }

  assert {
    condition     = local.servers["accounts-service-02"].subnet != "private-az3"
    error_message = "A group's new server goes where it has none."
  }
}

run "blueprint_values_refused" {
  command = plan

  variables {
    config_dir     = "tests/on-blueprints-refused"
    blueprints_dir = "../../blueprints/compute"
    scripts_dir    = "../../scripts"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "sso.yml: listener_rule needs listener_arn (<load balancer>/<port>, such as services/443), priority, and a condition: host_header.values and/or path_pattern.values"),
      contains(local.problems, "admin-portal.yml: host_header Admin Portal is a full host name, lowercase, such as admin-portal-operations.<domain>: names are never filled in"),
      contains(local.problems, "admin-portal.yml: listener rule priorities are 1000 and up (1 to 999 are the load balancer's own rules)"),
    ])
    error_message = "Host names that are not a list of host names, and a priority a listener rule cannot take, are each named."
  }

  expect_failures = [output.servers]
}

run "groups_in_folders" {
  command = plan

  variables {
    config_dir     = "tests/in-folders"
    blueprints_dir = "tests/blueprints"
  }

  assert {
    condition     = length(local.problems) == 0 && toset(keys(module.server_group)) == toset(["accounts-service", "billing-service"]) && local.file_paths["accounts-service"] == "apps/services/accounts-service.yml"
    error_message = "Group files are found in folders of any depth, each named by its file."
  }
}

run "refuses_one_name_in_two_folders" {
  command = plan

  variables {
    config_dir     = "tests/in-folders-clash"
    blueprints_dir = "tests/blueprints"
  }

  assert {
    condition     = contains(local.problems, "accounts-service.yml is in more than one folder (apps/accounts-service.yml, infra/accounts-service.yml); a group's name is its file's, so it must be unique")
    error_message = "Two files of one name, in different folders, are refused rather than one silently winning."
  }

  expect_failures = [output.servers]
}

run "refuses_a_short_host" {
  command = plan

  variables {
    config_dir     = "tests/short-hosts"
    blueprints_dir = "../../blueprints/compute"
    scripts_dir    = "../../scripts"
  }

  override_data {
    target = data.aws_lb_listener.listeners["staff:443"]
    values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/staff/abc/def" }
  }

  assert {
    condition     = contains(local.problems, "admin-portal.yml: host_header admin-portal is a full host name, lowercase, such as admin-portal-operations.<domain>: names are never filled in") && length(local.names) == 0
    error_message = "A host is written in full, and gets no DNS record of its own: public names are only ever written where a file names the zone."
  }

  expect_failures = [output.servers]
}

run "records_in_the_zone_they_name" {
  command = plan

  variables {
    config_dir = "tests/named"
  }

  assert {
    condition     = local.names[0].name == "grafana.operations.corp.internal" && local.names[0].private && local.names[0].own
    error_message = "A record in the environment's own private zone is written with its own account."
  }

  assert {
    condition     = local.names[1].name == "grafana-operations.example.com" && !local.names[1].private && !local.names[1].own
    error_message = "A record in a public domain is written through the hub."
  }
}

run "refuses_a_zone_that_is_not_a_public_domain" {
  command = plan

  variables {
    config_dir = "tests/unlisted-zone"
  }

  assert {
    condition     = contains(local.problems, "grafana.yml: grafana-operations.otherbrand.com is in otherbrand.com, which is not a private zone nor one of dns.public_domain in config/global.yml")
    error_message = "A public name goes only in a domain listed in config/global.yml."
  }

  expect_failures = [output.servers]
}

run "a_listener_rule_written_out" {
  command = plan

  variables {
    config_dir     = "tests/native-rule"
    blueprints_dir = "../../blueprints/compute"
    scripts_dir    = "../../scripts"
  }

  override_data {
    target = data.aws_lb_listener.listeners["public:443"]
    values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/public/abc/def" }
  }

  assert {
    condition     = length(local.problems) == 0 && length(local.routes) == 1 && local.routes[0].load_balancer == "public" && local.routes[0].listener == "443" && local.routes[0].priority == 1040 && jsonencode(local.routes[0].hosts) == jsonencode(["customer-staging.example.internal"])
    error_message = "The app's listener_rule is the rule: its load balancer, port, priority and host names, as written."
  }

  assert {
    condition     = local.server_names["ocp01"] == "ocp01.operations.corp.internal" && local.server_names["ocp02"] == "ocp02.operations.corp.internal"
    error_message = "Its servers' internal names come from the blueprint's DNS tag, with nothing to write."
  }

  assert {
    condition     = length(local.names) == 0
    error_message = "A host name in the rule writes no DNS: a public record is its own file in the records stack."
  }
}

run "refuses_what_aws_does_not_call_it" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "grafana.yml: keys are count, server_name, instance_type, ami, tier, iam_instance_profile, vpc_security_group_ids, root_block_device, ebs_block_device, user_data, members, tags, autoscaling_group, autoscaling_policy, target_group, listener_rule, target_group_attachments, route53_records"),
      contains(local.problems, "grafana.yml: user_data is scripts/<name>, a file in the repository's scripts/ folder; boot.sh is not one"),
      contains(local.problems, "grafana.yml: target_group.stickiness takes the arguments of aws_lb_target_group's stickiness: enabled, type, cookie_duration, cookie_name, with type lb_cookie or app_cookie"),
      contains(local.problems, "grafana.yml: route53_records is a list of records, each with the arguments of aws_route53_record: name, type, zone_id, alias; alias takes name (a load balancer of this environment) and evaluate_target_health"),
      contains(local.problems, "grafana.yml: the record grafana needs name, type (A or AAAA), zone_id, alias.name and alias.evaluate_target_health"),
      contains(local.problems, "zabbix-proxy.yml: target_group_attachments is a list, each with the arguments of aws_lb_target_group_attachment: target_group_arn (a load balancer stack's target group, <load balancer>-<target>, or its ARN) and port"),
      contains(local.problems, "reports.yml: autoscaling_policy.target_tracking_configuration takes what aws_autoscaling_policy's does: predefined_metric_specification (predefined_metric_type, resource_label) and target_value"),
      contains(local.problems, "zabbix-proxy.yml: zabbix.example.com is not in its zone_id operations.corp.internal; name is the record's full name"),
      contains(local.problems, "hosts.yml: members.hosts-01 takes subnet_id, instance_type, private_ip, secondary_private_ips, tags"),
      contains(local.problems, "hosts.yml: ebs_block_device is a list of disks, each with device_name, volume_size, iops, throughput, tags, and device_name and volume_size required"),
      contains(local.problems, "hosts.yml: {server} fills in a blueprint's value; a file writes the value itself"),
    ])
    error_message = "The old shortcuts are refused, each naming the provider's arguments."
  }

  expect_failures = [output.servers]
}

run "backup_is_a_tag" {
  command = plan

  variables {
    config_dir     = "tests/blueprinted"
    blueprints_dir = "tests/blueprints"
  }

  assert {
    condition     = local.group_tags["accounts-service"].Backup == "standard" && !contains(keys(local.group_tags["grafana"]), "Backup")
    error_message = "A server is backed up when its tags say Backup: standard, as the blueprint's do; a file without the tag is not backed up."
  }
}

run "refuses_a_blueprint_role_in_other_keys" {
  command = plan

  variables {
    config_dir     = "tests/blueprinted"
    blueprints_dir = "tests/old-role-blueprints"
  }

  assert {
    condition     = contains(local.problems, "blueprints/compute/backend-service/v1.yml: role takes managed_policy_arns and statement, as the iam stack's roles do; every statement needs effect, actions and resources")
    error_message = "A blueprint's role is written in the iam stack's keys; managed_policies and policies are refused."
  }

  expect_failures = [output.servers]
}

run "a_named_image" {
  command = plan

  variables {
    config_dir = "tests/named-images"
    amis_dir   = "tests/amis-good"
  }

  assert {
    condition     = length(local.problems) == 0 && contains(keys(data.aws_ami.images), "ubuntu-2404") && length(data.aws_ami.images) == 1
    error_message = "A name is found through its file in config/amis/, and an ami- id passes through with no lookup."
  }
}

run "an_image_the_instance_type_cannot_run" {
  command = plan

  variables {
    config_dir = "tests/named-images"
    amis_dir   = "tests/amis-good"
  }

  override_data {
    target = data.aws_ami.images["ubuntu-2404"]
    values = { id = "ami-0aaaaaaaaaaaaaaaa", root_device_name = "/dev/xvda", architecture = "arm64" }
  }

  expect_failures = [output.servers]
}

run "refuses_an_image_that_can_change_by_itself" {
  command = plan

  variables {
    config_dir = "tests/named-images-bad"
    amis_dir   = "tests/amis-bad"
  }

  expect_failures = [output.servers]

  assert {
    condition = alltrue([
      contains(local.problems, "ami missing is neither an ami- id nor a file in config/amis/ (missing.yml)"),
      contains(local.problems, "config/amis/latest.yml: keys are owners, filter, include_deprecated, as data.aws_ami takes them; most_recent and name_regex are refused, so an image changes only in a reviewed commit"),
      contains(local.problems, "config/amis/latest.yml: filter needs name, with one exact image name and no wildcard, so the image cannot change by itself"),
      contains(local.problems, "config/amis/ownerless.yml: owners is a list, such as amazon, self or an account id"),
    ])
    error_message = "A missing image, a search, a wildcard and a file with no owner are each refused by name."
  }
}

