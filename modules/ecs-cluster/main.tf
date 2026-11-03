# Every command run through ECS Exec, and its output, is kept here.
resource "aws_cloudwatch_log_group" "exec" {
  name              = "/ecs/${var.environment}/exec"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = { Name = "${var.environment}-ecs-exec" }
}

resource "aws_ecs_cluster" "cluster" {
  name = var.environment

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec.name
        cloud_watch_encryption_enabled = var.log_kms_key_arn != null
      }
    }
  }

  tags = { Name = var.environment }
}

# Fargate by default; a service may ask for Fargate Spot for some or all of its tasks.
resource "aws_ecs_cluster_capacity_providers" "cluster" {
  cluster_name       = aws_ecs_cluster.cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}
