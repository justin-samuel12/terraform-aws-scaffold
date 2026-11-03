output "services" {
  description = "Service file -> its ECS service, task definition family, task role (its identity, for Vault) and, for blue/green, the CodeDeploy application and group a pipeline deploys to."
  value = {
    for name, s in module.ecs_service : name => {
      service         = s.service_name
      task_definition = s.task_definition.family
      task_role       = s.roles.task
      codedeploy      = s.codedeploy
    }
  }

  precondition {
    condition     = local.usable
    error_message = "The service files are not usable: ${join("; ", local.problems)}."
  }
}

output "cluster" {
  description = "The environment's cluster in this region, or null when there are no service files."
  value       = try({ name = module.ecs_cluster[0].name, arn = module.ecs_cluster[0].arn }, null)
}
