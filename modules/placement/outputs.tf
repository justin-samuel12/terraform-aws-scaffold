output "servers" {
  description = "Server name -> its group, its number in the group (01), Subnet tag, instance type and chosen addresses (primary first; empty for AWS-assigned)."
  value       = { for name, s in local.addressed : name => { group = s.group, index = s.index, subnet = s.subnet, type = s.type, private_ip = s.private_ip, secondary_ips = s.secondary_ips, addresses = s.addresses } }
}

output "problems" {
  description = "Why the placement is not usable; empty when it is."
  value       = local.problems
}
