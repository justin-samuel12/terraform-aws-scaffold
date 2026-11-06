output "vpc_id" {
  description = "This network's VPC."
  value       = module.vpc.vpc_id

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The network's files are not usable: ${join("; ", local.problems)}."
  }
}

output "subnet_ids" {
  description = "Tier -> subnet ids, one per availability zone."
  value       = module.vpc.subnet_ids
}

output "network" {
  description = "This VPC's entry in the IP plan: range, segment, zones and subnets per tier."
  value       = local.network
}

output "subnets" {
  description = "Subnet name (data-az1) -> id, CIDR and zone ID."
  value       = module.vpc.subnets
}

output "peering_connection_ids" {
  description = "Peering name (its file in config/peering/) -> the peering connection's id."
  value       = { for name, p in aws_vpc_peering_connection.peerings : name => p.id }
}
