output "service_name" {
  description = "The ECS service's name, <environment>-<name>."
  value       = local.service_name
}

output "task_definition" {
  description = "The latest task definition's family and ARN; with blue_green, the revision a deployment's AppSpec names."
  value       = { family = aws_ecs_task_definition.task.family, arn = aws_ecs_task_definition.task.arn }
}

output "roles" {
  description = "The task role (the application's identity, for Vault and its own permissions) and the execution role (ECS starting it)."
  value       = { task = aws_iam_role.task.arn, execution = aws_iam_role.execution.arn }
}

output "target_group_names" {
  description = "Its target groups: primary for rolling, blue and green for blue_green."
  value       = { for k, t in aws_lb_target_group.targets : k => t.name }
}

output "codedeploy" {
  description = "The CodeDeploy application and deployment group a pipeline deploys to, and the container and port its AppSpec names; null for rolling."
  value = local.blue_green ? {
    application      = aws_codedeploy_app.application[0].name
    deployment_group = aws_codedeploy_deployment_group.group[0].deployment_group_name
    container_name   = local.front.name
    container_port   = local.front.port
  } : null
}
