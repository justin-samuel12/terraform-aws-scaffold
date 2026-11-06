output "transit_gateway_id" {
  description = "This region's hub."
  value       = module.transit_gateway.transit_gateway_id
}

output "route_table_ids" {
  description = "Hub route table name -> id."
  value       = module.transit_gateway.route_table_ids
}

output "network" {
  description = "This VPC's entry in the IP plan: range, segment, zones and subnets per tier."
  value       = local.network
}

output "vpc_id" {
  description = "The egress VPC."
  value       = module.vpc.vpc_id
}

output "subnets" {
  description = "Subnet name (data-az1) -> id, CIDR and zone ID."
  value       = module.vpc.subnets
}

output "prefix_list_ids" {
  description = "Prefix list name -> id."
  value       = module.prefix_list.ids
}

output "dns" {
  description = "The inbound endpoint's addresses for HQ to forward to, and domain -> forwarding rule id."
  value = {
    inbound_ips = try(module.route53_resolver[0].inbound_ips, [])
    rule_ids    = try(module.route53_resolver[0].rule_ids, {})
  }
}

output "directory" {
  description = "The AWS Managed Microsoft AD, when config/global.yml enables it and this is the primary hub: its id, domain, domain controller addresses and the secret holding its Admin password; null otherwise."
  value = local.directory ? {
    id               = module.managed_directory[0].id
    name             = module.ip_plan.directory.name
    dns_ip_addresses = module.managed_directory[0].dns_ip_addresses
    admin_secret_arn = module.managed_directory[0].admin_secret_arn
  } : null
}
