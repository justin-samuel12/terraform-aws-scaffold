output "name" {
  description = "The application's name, which a pipeline deploys to."
  value       = var.name
}

output "deployment_groups" {
  description = "Its deployment groups in this environment: master, development and adhoc, or primary-<environment> when containerized."
  value       = sort(keys(aws_codedeploy_deployment_group.groups))
}

output "managed_here" {
  description = "false when a shared application is owned by another environment, and this one only adds its group."
  value       = local.manage
}
