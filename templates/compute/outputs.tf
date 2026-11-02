output "servers" {
  description = "Server name -> its group, subnet, chosen addresses (if any), and once built its instance id and private address."
  value = {
    for name, s in local.servers : name => merge(
      { group = s.group, subnet = s.subnet, chosen = s.addresses },
      try(module.server_group[s.group].servers[name], {}),
    )
  }

  precondition {
    condition     = local.usable
    error_message = "The group files are not usable: ${join("; ", local.problems)}."
  }
}

output "codedeploy_applications" {
  description = "Group -> the CodeDeploy application to deploy to, for the groups CodeDeploy deploys."
  value       = { for group, g in module.server_group : group => g.codedeploy_application if g.codedeploy_application != null }
}

output "autoscaling_groups" {
  description = "Group -> its Auto Scaling group's name, for the groups that scale."
  value       = { for group, g in module.server_group : group => g.autoscaling_group if g.autoscaling_group != null }
}
