output "servers" {
  description = "Server name -> instance id and private address."
  value       = module.servers.servers
}

output "target_group_names" {
  description = "Every target group its servers are in, its own and any load balancer's, for deployments that drain servers first."
  value       = local.target_group_names
}

output "size" {
  description = "How many servers it has: its fixed servers, or an Auto Scaling group's largest size."
  value       = var.autoscaling == null ? length(var.servers.members) : var.autoscaling.max_size
}

output "autoscaling_group" {
  description = "The Auto Scaling group's name, or null for fixed servers."
  value       = try(module.autoscaling[0].name, null)
}
