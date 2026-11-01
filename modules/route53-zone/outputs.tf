output "public" {
  description = "Public zone -> its id and the name servers to set at the registrar."
  value       = { for name, zone in aws_route53_zone.public : name => { id = zone.zone_id, name_servers = zone.name_servers } }
}

output "private" {
  description = "Private zone -> id."
  value       = { for name, zone in aws_route53_zone.private : name => zone.zone_id }
}
