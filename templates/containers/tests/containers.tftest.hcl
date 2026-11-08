mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-1", "subnet-2", "subnet-3"] }
  }
  mock_data "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:loadbalancer/app/operations-internal/abc", arn_suffix = "app/operations-internal/abc" }
  }
  mock_data "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/operations-internal/abc/def" }
  }
  mock_data "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-operations" }
}

variables {
  config_path = "../../tests/config"
  environment = "operations"
  region      = "us-east-2"
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.services == {} && output.cluster == null && length(module.ecs_cluster) == 0
    error_message = "Without files, no cluster and no services."
  }
}

run "rolling" {
  command = plan

  variables {
    config_dir = "tests/rolling"
  }

  override_data {
    target = data.aws_subnet.subnets["private-az1"]
    values = { id = "subnet-private-1" }
  }

  override_data {
    target = data.aws_security_group.groups["orders-api"]
    values = { id = "sg-orders-api" }
  }

  assert {
    condition     = length(local.problems) == 0 && length(module.ecs_cluster) == 1 && length(module.codedeploy_role) == 0
    error_message = "The files are usable; the cluster is made, and no CodeDeploy role without a CODE_DEPLOY service."
  }

  assert {
    condition     = local.containers["orders-api"][0].name == "orders-api" && local.ported["orders-api"][0].portMappings[0].containerPort == 8080 && local.containers["orders-api"][0].secrets[0].valueFrom == "arn:aws:secretsmanager:us-east-2:111111111111:secret:operations/orders/database-AbCdEf"
    error_message = "container_definitions are the task definition's own: portMappings, and secrets by ARN."
  }

  assert {
    condition     = jsonencode([for c in local.containers.worker : c.name]) == jsonencode(["worker", "sidecar"]) && !local.containers.worker[1].essential && local.containers.worker[0].essential == null && jsonencode(local.containers.worker[1].healthCheck.command) == jsonencode(["CMD-SHELL", "exit 0"])
    error_message = "Several containers, in order; essential only where a file says it."
  }

  assert {
    condition     = module.ecs_service["orders-api"].service_name == "operations-orders-api" && jsonencode(local.subnet_names.worker) == jsonencode(["ops-az1", "subnet-0123456789abcdef0"]) && toset(keys(data.aws_subnet.subnets)) == toset(["private-az1", "private-az2", "private-az3", "ops-az1"]) && toset(keys(data.aws_security_group.groups)) == toset(["orders-api", "workers"])
    error_message = "Subnets and groups are found by name; an ID passes through unchanged."
  }

  assert {
    condition     = local.routes[0].listener == "443" && jsonencode(local.routes[0].hosts) == jsonencode(["orders.example.com"]) && jsonencode(local.listener_keys) == jsonencode(["internal:443"])
    error_message = "A rule is on port 443 of the named load balancer unless it says otherwise."
  }

  assert {
    condition     = local.controller["orders-api"] == "ECS" && local.controller.worker == "ECS"
    error_message = "ECS deploys unless a file names another deployment_controller, as the provider does."
  }

  assert {
    condition     = output.services["orders-api"].service == "operations-orders-api" && output.services["orders-api"].codedeploy == null
    error_message = "Named <environment>-<name>, with no CodeDeploy for an ECS deployment."
  }
}

run "code_deploy_canary" {
  command = plan

  variables {
    config_dir = "tests/blue-green"
  }

  assert {
    condition     = length(local.problems) == 0 && local.blue_green == toset(["checkout"]) && length(module.codedeploy_role) == 1
    error_message = "A CODE_DEPLOY service brings the environment's CodeDeploy role."
  }

  assert {
    condition     = jsonencode(local.routes[0].paths) == jsonencode(["/api/*"]) && local.routes[0].priority == 1300
    error_message = "Host and path both match."
  }

  assert {
    condition     = output.services.checkout.codedeploy.application == "operations-checkout" && output.services.checkout.codedeploy.deployment_group == "operations-checkout" && output.services.checkout.codedeploy.container_port == 3000
    error_message = "A CodeDeploy application and group named after the service, deploying the checkout container on port 3000."
  }
}

run "refused" {
  command = plan

  variables {
    config_dir = "tests/refused"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "typo.yml: keys are ${join(", ", local.file_keys)}, as aws_ecs_service and aws_ecs_task_definition take them"),
      contains(local.problems, "typo.yml: a container in container_definitions takes ${join(", ", local.definition_keys)}, and needs name and image"),
      contains(local.problems, "shortcut.yml: keys are ${join(", ", local.file_keys)}, as aws_ecs_service and aws_ecs_task_definition take them"),
      contains(local.problems, "shortcut.yml: needs cpu, memory, desired_count"),
      contains(local.problems, "shortcut.yml: container_definitions is a list of at least one container"),
      contains(local.problems, "canary.yml: deployment_group is CodeDeploy's (all at once, canary, linear), so it needs deployment_controller.type CODE_DEPLOY; an ECS deployment is ECS's own"),
      contains(local.problems, "leaky.yml: DB_PASSWORD looks like a secret: environment never holds one; list it under secrets with valueFrom: <ARN of a Secrets Manager secret or Parameter Store parameter>"),
      contains(local.problems, "leaky.yml: a secret's valueFrom is the full ARN of a Secrets Manager secret or Parameter Store parameter, never the value itself"),
      contains(local.problems, "leaky.yml: container names leaky are used more than once; each container's name is its own"),
      contains(local.problems, "servers.yml: CodeDeployDefault.OneAtATime is for servers; a service uses an ECS one, such as CodeDeployDefault.ECSAllAtOnce, CodeDeployDefault.ECSCanary10Percent5Minutes or CodeDeployDefault.ECSLinear10PercentEvery1Minutes"),
      contains(local.problems, "servers.yml: listener rule priorities are 1000 and up (1 to 999 are the load balancer's own rules)"),
      anytrue([for p in local.problems : startswith(p, "servers.yml: network_configuration.subnets lists the subnets, by name such as private-az1")]),
    ])
    error_message = "A misspelt key, the old shortcuts, a CodeDeploy setting on an ECS deployment, a secret in the environment, a secret that is not an ARN, two containers of one name, a server deployment config, a low priority and an unknown subnet are each named."
  }

  assert {
    condition     = length(module.ecs_service) == 0 && length(module.ecs_cluster) == 0
    error_message = "Nothing is built from unusable files."
  }

  expect_failures = [output.services]
}

run "refuses_one_name_in_two_folders" {
  command = plan

  variables {
    config_dir = "tests/two-folders"
  }

  assert {
    condition     = contains(local.problems, "report.yml is in more than one folder (a/report.yml, b/report.yml); a service's name is its file's, so it must be unique")
    error_message = "Two files of one name are refused rather than one silently winning."
  }

  expect_failures = [output.services]
}

run "on_a_blueprint" {
  command = plan

  variables {
    config_dir     = "tests/on-blueprints"
    blueprints_dir = "../../blueprints/containers"
  }

  assert {
    condition     = length(local.problems) == 0 && local.blue_green == toset(["payments-api", "ledger-api"])
    error_message = "Both services are usable, deployed by CodeDeploy as the blueprint says."
  }

  assert {
    condition     = local.files["payments-api"].runtime_platform.cpu_architecture == "X86_64" && local.files["ledger-api"].runtime_platform.cpu_architecture == "ARM64"
    error_message = "A service runs on X86_64 unless its own file chooses ARM64."
  }

  assert {
    condition     = local.files["payments-api"].cpu == 1024 && local.files["payments-api"].memory == 2048 && local.files["ledger-api"].cpu == 512 && local.files["ledger-api"].memory == 1024
    error_message = "cpu and memory are the app's where it gives them, the blueprint's where it does not."
  }

  assert {
    condition     = local.files["payments-api"].appautoscaling_target.max_capacity == 10 && local.files["payments-api"].appautoscaling_target.min_capacity == 2 && local.files["payments-api"].appautoscaling_policy.target_tracking_scaling_policy_configuration.target_value == 60
    error_message = "Raising its ceiling keeps the rest of the blueprint's scaling."
  }

  assert {
    condition     = jsonencode(local.files["payments-api"].listener_rule.condition.path_pattern.values) == jsonencode(["/payments-api/*"]) && local.files["payments-api"].listener_rule.priority == 1400 && local.files["payments-api"].listener_rule.listener_arn == "services/443" && local.files["payments-api"].target_group.health_check.path == "/payments-api/status"
    error_message = "Reached by its own path, at its own priority, checked at /{app}/status."
  }

  assert {
    condition     = jsonencode(local.subnet_names["payments-api"]) == jsonencode(["private-az1", "private-az2", "private-az3"]) && jsonencode(local.group_names["payments-api"]) == jsonencode(["ecs-services", "services-lb-clients", "sqlserver-clients", "payments-files"]) && jsonencode(local.group_names["ledger-api"]) == jsonencode(["ecs-services", "services-lb-clients", "sqlserver-clients"])
    error_message = "A service's own security groups are added to the blueprint's; the blueprint's subnets stay."
  }
}
