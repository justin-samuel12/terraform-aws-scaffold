output "load_balancers" {
  description = "Load balancer name -> its DNS name and target group ARNs."
  value       = { for name, lb in module.load_balancer : name => { dns_name = lb.dns_name, target_group_arns = lb.target_group_arns } }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The load balancer files are not usable: ${join("; ", local.problems)}."
  }
}
