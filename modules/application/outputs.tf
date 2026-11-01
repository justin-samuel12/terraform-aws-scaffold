output "servers" {
  description = "Server name -> instance id and private address."
  value       = module.servers.servers
}

output "codedeploy_application" {
  description = "The CodeDeploy application to deploy to, or null when it is not deployed by CodeDeploy."
  value       = try(aws_codedeploy_app.application[0].name, null)
}
