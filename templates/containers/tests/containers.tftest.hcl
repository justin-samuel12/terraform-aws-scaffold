# Service files turned into Fargate services, against a mocked AWS -- docs/containers.md.
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

  assert {
    condition     = length(local.problems) == 0 && length(module.ecs_cluster) == 1 && length(module.codedeploy_role) == 0
    error_message = "The files are usable; the cluster is made, and no CodeDeploy role without a blue/green service."
  }

  assert {
    condition     = local.containers["orders-api"][0].name == "orders-api" && local.containers["orders-api"][0].port == 8080 && local.containers["orders-api"][0].secrets.DATABASE_URL == "arn:aws:secretsmanager:us-east-2:111111111111:secret:operations/orders/database-AbCdEf"
    error_message = "image and port make one container named after the service, its secrets by ARN."
  }

  assert {
    condition     = [for c in local.containers.worker : c.name] == ["worker", "sidecar"] && !local.containers.worker[1].essential && local.containers.worker[1].health_check.command == ["CMD-SHELL", "exit 0"]
    error_message = "container_definitions make several, in order."
  }

  assert {
    condition     = local.routes[0].listener == "443" && local.routes[0].hosts == ["orders.example.com"] && local.listener_keys == tolist(["internal:443"])
    error_message = "A rule is on port 443 of the named load balancer unless it says otherwise."
  }

  assert {
    condition     = local.strategy["orders-api"] == "rolling" && local.strategy.worker == "rolling"
    error_message = "Rolling unless a file says otherwise."
  }

  assert {
    condition     = output.services["orders-api"].service == "operations-orders-api" && output.services["orders-api"].codedeploy == null
    error_message = "Named <environment>-<name>, with no CodeDeploy for a rolling service."
  }
}

run "blue_green_canary" {
  command = plan

  variables {
    config_dir = "tests/blue-green"
  }

  assert {
    condition     = length(local.problems) == 0 && local.blue_green == toset(["checkout"]) && length(module.codedeploy_role) == 1
    error_message = "A blue/green service brings the environment's CodeDeploy role."
  }

  assert {
    condition     = local.routes[0].paths == ["/api/*"] && local.routes[0].priority == 1300
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
      contains(local.problems, "typo.yml: keys are ${join(", ", local.file_keys)}"),
      contains(local.problems, "canary.yml: deployment_config_name is CodeDeploy's (all at once, canary, linear), so it needs strategy: blue_green; a rolling deployment is ECS's own"),
      contains(local.problems, "leaky.yml: DB_PASSWORD looks like a secret: environment variables never hold one; list it under secrets as NAME: <ARN of a Secrets Manager secret or Parameter Store parameter>"),
      contains(local.problems, "leaky.yml: secrets are NAME: <the full ARN of a Secrets Manager secret or Parameter Store parameter>, never the value itself"),
      contains(local.problems, "servers.yml: CodeDeployDefault.OneAtATime is for servers; a service uses an ECS one, such as CodeDeployDefault.ECSAllAtOnce, CodeDeployDefault.ECSCanary10Percent5Minutes or CodeDeployDefault.ECSLinear10PercentEvery1Minutes"),
      contains(local.problems, "servers.yml: listener rule priorities are 1000 and up (1 to 999 are the load balancer's own rules)"),
    ])
    error_message = "A misspelt key, a canary on a rolling service, a secret in the environment, a secret that is not an ARN, a server deployment config and a low priority are each named."
  }

  assert {
    condition     = length(module.ecs_service) == 0 && length(module.ecs_cluster) == 0
    error_message = "Nothing is built from unusable files."
  }

  expect_failures = [output.services]
}
