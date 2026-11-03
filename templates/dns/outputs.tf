output "public" {
  description = "Public zone -> id and the name servers to set at the registrar."
  value       = module.route53_zone.public
}

output "private" {
  description = "Private zone -> id."
  value       = module.route53_zone.private

  precondition {
    condition     = length(local.foreign_hubs) == 0
    error_message = "Private zones reach hubs in the primary hub's account (${local.primary_account}) only, and the hub in ${join(", ", local.foreign_hubs)} is in another. Put every hub in one account, or leave dns.private_zones empty."
  }
}
