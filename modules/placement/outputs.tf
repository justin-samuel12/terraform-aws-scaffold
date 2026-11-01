output "servers" {
  description = "Server name -> its group, Subnet tag, instance type and chosen addresses (role -> address; empty for AWS-assigned)."
  value       = { for name, s in local.addressed : name => { group = s.group, subnet = s.subnet, type = s.type, addresses = s.addresses } }
}

output "problems" {
  description = "Why the placement is not usable; empty when it is."
  value       = local.problems
}
