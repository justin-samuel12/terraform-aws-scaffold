mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    override_during = plan
    defaults        = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/ecs/development-orders-api" }
  }
}

variables {
  name        = "orders-api"
  environment = "development"
  region      = "us-east-1"
  cluster     = { arn = "arn:aws:ecs:us-east-1:111111111111:cluster/development", name = "development" }
  execute_command = {
    log_group_arn = "arn:aws:logs:us-east-1:111111111111:log-group:/ecs/development/exec"
    kms_key_arn   = "arn:aws:kms:us-east-1:111111111111:key/mrk-data"
  }
  cpu           = 512
  memory        = 1024
  desired_count = 2
  container_definitions = [{
    name         = "orders-api"
    image        = "111111111111.dkr.ecr.us-east-1.amazonaws.com/orders-api:1.4.2"
    portMappings = [{ containerPort = 8080 }]
    environment  = [{ name = "LOG_LEVEL", value = "info" }]
    secrets = [
      { name = "DATABASE_URL", valueFrom = "arn:aws:secretsmanager:us-east-1:111111111111:secret:development/orders/database-AbCdEf:url::" },
      { name = "FEATURE_KEYS", valueFrom = "arn:aws:ssm:us-east-1:111111111111:parameter/development/orders/features" },
    ]
  }]
  network_configuration = { subnets = ["subnet-1", "subnet-2", "subnet-3"], security_groups = ["sg-orders-api"] }
  vpc_id                = "vpc-development"
  health_check          = { path = "/health" }
  routes                = [{ listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/development-internal/abc/def", hosts = ["orders.example.com"], priority = 1200 }]
  statements = [{
    actions   = ["sqs:SendMessage"]
    resources = ["arn:aws:sqs:us-east-1:111111111111:development-orders"]
    condition = [{ test = "StringEquals", variable = "aws:ResourceTag/Service", values = ["orders-api"] }]
  }]
}

run "rolling" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.service) == 1 && length(aws_ecs_service.blue_green) == 0 && aws_ecs_service.service[0].deployment_controller[0].type == "ECS" && aws_ecs_service.service[0].deployment_circuit_breaker[0].rollback
    error_message = "A rolling service is ECS's own deployment, with the circuit breaker rolling back."
  }

  assert {
    condition     = aws_appautoscaling_target.service.min_capacity == var.desired_count && aws_appautoscaling_target.service.max_capacity == var.desired_count && length(aws_appautoscaling_policy.service) == 0
    error_message = "Without autoscaling the count is held at desired_count by the same scaling target, so adding autoscaling later changes it in place, never replacing the service."
  }

  assert {
    condition     = !aws_ecs_service.service[0].network_configuration[0].assign_public_ip && aws_ecs_service.service[0].enable_execute_command && aws_ecs_service.service[0].deployment_minimum_healthy_percent == null && aws_ecs_service.service[0].name == "development-orders-api"
    error_message = "Private, no public address, ECS Exec on as asked, named <environment>-<name>, the deployment percentages the provider's."
  }

  assert {
    condition     = keys(aws_lb_target_group.targets) == ["primary"] && aws_lb_target_group.targets["primary"].target_type == "ip" && startswith(aws_lb_target_group.targets["primary"].name, "development-orders-api-") && length(aws_lb_target_group.targets["primary"].name) <= 32 && aws_lb_listener_rule.routes["0"].priority == 1200
    error_message = "One target group of task IPs, and its rule on the shared listener."
  }

  assert {
    condition     = aws_iam_role.task.name == "development-orders-api-us-east-1" && aws_iam_role.execution.name == "development-orders-api-us-east-1-execution"
    error_message = "A task role of its own, <environment>-<name>-<region>, and an execution role beside it."
  }

  assert {
    condition = alltrue([
      contains(jsondecode(aws_iam_role_policy.execution.policy).Statement[1].Resource, "arn:aws:ecr:us-east-1:111111111111:repository/orders-api"),
      contains(flatten([for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s.Resource]), "arn:aws:secretsmanager:us-east-1:111111111111:secret:development/orders/database-AbCdEf"),
      contains(flatten([for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : s.Resource]), "arn:aws:ssm:us-east-1:111111111111:parameter/development/orders/features"),
    ])
    error_message = "The execution role pulls its own repository and reads only the listed secrets."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.task[0].policy).Statement[0].Action == ["sqs:SendMessage"] && jsondecode(aws_iam_role_policy.task[0].policy).Statement[0].Condition == { StringEquals = { "aws:ResourceTag/Service" = ["orders-api"] } } && length(jsondecode(aws_iam_role_policy.task[0].policy).Statement) == 5
    error_message = "The task role has the file's permissions, with their condition, and ECS Exec's."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.task.container_definitions)[0].secrets[0] == { name = "DATABASE_URL", valueFrom = var.container_definitions[0].secrets[0].valueFrom } && jsonencode(jsondecode(aws_ecs_task_definition.task.container_definitions)[0].environment) == jsonencode([{ name = "LOG_LEVEL", value = "info" }]) && !can(jsondecode(aws_ecs_task_definition.task.container_definitions)[0].essential) && length(aws_ecs_task_definition.task.runtime_platform) == 0
    error_message = "Secrets reach the container by ARN, never as values; what the file leaves out (essential, runtime_platform) is not written."
  }

  assert {
    condition     = aws_cloudwatch_log_group.service.retention_in_days == 365 && aws_ecs_task_definition.task.network_mode == "awsvpc" && aws_ecs_task_definition.task.requires_compatibilities == toset(["FARGATE"])
    error_message = "Fargate, awsvpc, logs kept a year."
  }

  assert {
    condition     = output.codedeploy == null && length(aws_codedeploy_app.application) == 0
    error_message = "No CodeDeploy for a rolling service."
  }
}

run "scaled_on_requests" {
  command = plan

  variables {
    load_balancer_arn_suffix = "app/development-internal/abc"
    autoscaling = {
      min_capacity = 2
      max_capacity = 6
      target_tracking_scaling_policy_configuration = {
        target_value                    = 500
        predefined_metric_specification = { predefined_metric_type = "ALBRequestCountPerTarget" }
      }
    }
  }

  assert {
    condition     = length(aws_ecs_service.service) == 1 && aws_appautoscaling_target.service.resource_id == "service/development/development-orders-api" && aws_appautoscaling_target.service.max_capacity == 6
    error_message = "With autoscaling, the service that leaves its count to it, between 2 and 6."
  }
}

run "blue_green_canary" {
  command = plan

  variables {
    name                  = "checkout"
    codedeploy_role_arn   = "arn:aws:iam::111111111111:role/codedeploy-ecs-development-us-east-1"
    deployment_controller = "CODE_DEPLOY"
    deployment_group      = { deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes", termination_wait_time_in_minutes = 15 }
  }

  assert {
    condition     = aws_codedeploy_deployment_group.group[0].blue_green_deployment_config[0].terminate_blue_instances_on_deployment_success[0].termination_wait_time_in_minutes == 15
    error_message = "The old tasks are kept as long as the file says."
  }

  assert {
    condition     = length(aws_ecs_service.blue_green) == 1 && length(aws_ecs_service.service) == 0 && aws_ecs_service.blue_green[0].deployment_controller[0].type == "CODE_DEPLOY"
    error_message = "A blue/green service is CodeDeploy's to deploy."
  }

  assert {
    condition     = toset(keys(aws_lb_target_group.targets)) == toset(["blue", "green"]) && aws_lb_target_group.targets["blue"].name != aws_lb_target_group.targets["green"].name && length(aws_lb_listener_rule.routes_blue_green) == 1 && length(aws_lb_listener_rule.routes) == 0
    error_message = "Two target groups, and a rule CodeDeploy may move between them."
  }

  assert {
    condition     = aws_codedeploy_app.application[0].name == "development-checkout" && aws_codedeploy_app.application[0].compute_platform == "ECS" && aws_codedeploy_deployment_group.group[0].deployment_config_name == "CodeDeployDefault.ECSCanary10Percent5Minutes"
    error_message = "A CodeDeploy application named after the service, shifting traffic as a canary."
  }

  assert {
    condition     = aws_codedeploy_deployment_group.group[0].deployment_style[0].deployment_type == "BLUE_GREEN" && aws_codedeploy_deployment_group.group[0].auto_rollback_configuration[0].enabled && contains(aws_codedeploy_deployment_group.group[0].auto_rollback_configuration[0].events, "DEPLOYMENT_FAILURE")
    error_message = "Blue/green with traffic control, rolling back when a deployment fails."
  }

  assert {
    condition     = output.codedeploy.container_name == "orders-api" && output.codedeploy.container_port == 8080
    error_message = "The container and port a deployment's AppSpec names."
  }
}

run "refuses_code_deploy_without_a_deployment_config" {
  command = plan

  variables {
    codedeploy_role_arn   = "arn:aws:iam::111111111111:role/codedeploy-ecs-development-us-east-1"
    deployment_controller = "CODE_DEPLOY"
  }

  expect_failures = [var.deployment_group]
}

run "refuses_a_canary_on_a_rolling_service" {
  command = plan

  variables {
    deployment_group = { deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes" }
  }

  expect_failures = [var.deployment_group]
}

run "refuses_a_server_deployment_config" {
  command = plan

  variables {
    codedeploy_role_arn   = "arn:aws:iam::111111111111:role/codedeploy-ecs-development-us-east-1"
    deployment_controller = "CODE_DEPLOY"
    deployment_group      = { deployment_config_name = "CodeDeployDefault.OneAtATime" }
  }

  expect_failures = [var.deployment_group]
}

run "refuses_blue_green_without_routes" {
  command = plan

  variables {
    routes                = []
    codedeploy_role_arn   = "arn:aws:iam::111111111111:role/codedeploy-ecs-development-us-east-1"
    deployment_controller = "CODE_DEPLOY"
    deployment_group      = { deployment_config_name = "CodeDeployDefault.ECSAllAtOnce" }
  }

  expect_failures = [var.deployment_controller]
}

run "refuses_a_secret_in_the_environment" {
  command = plan

  variables {
    container_definitions = [{ name = "orders-api", image = "nginx:1.27", portMappings = [{ containerPort = 8080 }], environment = [{ name = "DB_PASSWORD", value = "hunter2" }] }]
  }

  expect_failures = [var.container_definitions]
}

run "refuses_a_secret_that_is_not_an_arn" {
  command = plan

  variables {
    container_definitions = [{ name = "orders-api", image = "nginx:1.27", portMappings = [{ containerPort = 8080 }], secrets = [{ name = "DATABASE_URL", valueFrom = "postgres://user:pass@db/orders" }] }]
  }

  expect_failures = [var.container_definitions]
}

run "worker_without_routes" {
  command = plan

  variables {
    routes                = []
    container_definitions = [{ name = "worker", image = "public.ecr.aws/docker/library/python:3.12", command = ["python", "worker.py"] }]
    statements            = []
  }

  assert {
    condition     = length(aws_lb_target_group.targets) == 0 && length(aws_ecs_service.service[0].load_balancer) == 0 && !anytrue([for s in jsondecode(aws_iam_role_policy.execution.policy).Statement : contains(s.Action, "ecr:GetAuthorizationToken")])
    error_message = "A worker: no target group, and no ECR permissions for an image from elsewhere."
  }
}

run "refuses_two_containers_of_one_name" {
  command = plan

  variables {
    container_definitions = [{ name = "orders-api", image = "nginx:1.27", portMappings = [{ containerPort = 8080 }] }, { name = "orders-api", image = "nginx:1.27" }]
  }

  expect_failures = [var.container_definitions]
}
