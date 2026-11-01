output "public" {
  description = "Public zone -> id and the name servers to set at the registrar."
  value       = module.route53_zone.public
}

output "private" {
  description = "Private zone -> id."
  value       = module.route53_zone.private
}
