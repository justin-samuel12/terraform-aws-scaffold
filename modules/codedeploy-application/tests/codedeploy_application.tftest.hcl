# Applications and deployment groups, against a mocked AWS -- docs/compute.md#deploying-with-codedeploy.
mock_provider "aws" {}

mock_provider "external" {
  mock_data "external" {
    defaults = { result = { exists = "true", owner = "staging" } }
  }
}

variables {
  name             = "external-api-service"
  environment      = "production"
  region           = "us-east-2"
  account_id       = "111111111111"
  service_role_arn = "arn:aws:iam::111111111111:role/codedeploy-production"
}

run "fixed_servers" {
  command = plan

  variables {
    selector                     = { key = "Function", value = "api" }
    target_group_names           = ["production-api-1a2b3c4d"]
    servers_behind_load_balancer = 2
  }

  assert {
    condition     = length(aws_codedeploy_app.application) == 1 && toset(keys(aws_codedeploy_deployment_group.groups)) == toset(["master", "development", "adhoc"])
    error_message = "One application, the same name in every environment, with a deployment group per branch."
  }

  assert {
    condition     = length(aws_codedeploy_deployment_group.groups["master"].ec2_tag_set) == 3 && aws_codedeploy_deployment_group.groups["master"].auto_rollback_configuration[0].enabled
    error_message = "Servers are found by their CodeDeploy:<app> tag, the environment and the selector; a failed deployment rolls back."
  }

  assert {
    condition     = aws_codedeploy_deployment_group.groups["master"].deployment_style[0].deployment_option == "WITH_TRAFFIC_CONTROL" && length(aws_codedeploy_deployment_group.groups["master"].load_balancer_info) == 1
    error_message = "With two servers behind a load balancer, each is drained before it is deployed to."
  }

  assert {
    condition     = length(data.external.ownership) == 0 && local.bootstrap_group == "adhoc"
    error_message = "A non-shared application needs no ownership check; a bootstrap would run on the last group."
  }
}

run "shared_application_owned_elsewhere" {
  command = plan

  variables {
    containerized = true
  }

  assert {
    condition     = length(aws_codedeploy_app.application) == 0 && !output.managed_here && toset(keys(aws_codedeploy_deployment_group.groups)) == toset(["primary-production"])
    error_message = "A shared application staging already owns is left to it; production only adds its own group."
  }
}

run "groups_from_config" {
  command = plan

  variables {
    groups = ["main", "release"]
  }

  assert {
    condition     = toset(keys(aws_codedeploy_deployment_group.groups)) == toset(["main", "release"]) && aws_codedeploy_deployment_group.groups["main"].deployment_style[0].deployment_option == "WITHOUT_TRAFFIC_CONTROL"
    error_message = "The group names come from config/; without servers behind a load balancer there is no traffic control."
  }
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    name = "External-API"
  }

  expect_failures = [var.name]
}
