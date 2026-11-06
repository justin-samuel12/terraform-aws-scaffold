output "servers" {
  description = "Server name -> its group, subnet, chosen addresses (if any), its name in the environment's private zone from its DNS tag, and once built its instance id and private address."
  value = {
    for name, s in local.servers : name => merge(
      { group = s.group, subnet = s.subnet, chosen = s.addresses, dns = try(local.server_names[name], null) },
      try(module.server_group[s.group].servers[name], {}),
    )
  }

  precondition {
    condition     = local.usable
    error_message = "The group files are not usable: ${join("; ", local.problems)}."
  }
}

output "codedeploy_applications" {
  description = "Application -> its deployment groups here, and whether this environment manages the application itself (a shared one may be another's)."
  value       = { for app, a in module.codedeploy_application : app => { deployment_groups = a.deployment_groups, managed_here = a.managed_here } }
}

output "autoscaling_groups" {
  description = "Group -> its Auto Scaling group's name, for the groups that scale."
  value       = { for group, g in module.server_group : group => g.autoscaling_group if g.autoscaling_group != null }
}
