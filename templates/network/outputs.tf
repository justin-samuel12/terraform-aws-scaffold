output "vpc_id" {
  description = "This network's VPC."
  value       = module.vpc.vpc_id
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
