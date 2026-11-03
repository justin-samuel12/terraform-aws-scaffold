# One cluster per environment and region, against a mocked AWS -- docs/containers.md.
mock_provider "aws" {}

variables {
  environment = "development"
  kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/mrk-data"
}

run "cluster" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.cluster.name == "development" && one([for s in aws_ecs_cluster.cluster.setting : s.value if s.name == "containerInsights"]) == "enabled"
    error_message = "Named after the environment, with Container Insights on."
  }

  assert {
    condition     = toset(aws_ecs_cluster_capacity_providers.cluster.capacity_providers) == toset(["FARGATE", "FARGATE_SPOT"]) && one(aws_ecs_cluster_capacity_providers.cluster.default_capacity_provider_strategy).capacity_provider == "FARGATE"
    error_message = "Fargate and Fargate Spot, Fargate by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.exec.retention_in_days == 365 && aws_ecs_cluster.cluster.configuration[0].execute_command_configuration[0].logging == "OVERRIDE" && aws_ecs_cluster.cluster.configuration[0].execute_command_configuration[0].kms_key_id == var.kms_key_arn
    error_message = "ECS Exec sessions encrypted with the data key and logged for a year."
  }
}

run "never_without_insights" {
  command = plan

  variables {
    container_insights = "disabled"
  }

  expect_failures = [var.container_insights]
}
