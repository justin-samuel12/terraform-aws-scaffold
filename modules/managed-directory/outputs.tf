output "id" {
  description = "The directory's id (d-...), which RDS joins with domain and Windows servers join by name."
  value       = aws_directory_service_directory.directory.id
}

output "dns_ip_addresses" {
  description = "The domain controllers' addresses, which answer for the domain."
  value       = aws_directory_service_directory.directory.dns_ip_addresses
}

output "security_group_id" {
  description = "The group AWS made for the domain controllers."
  value       = aws_directory_service_directory.directory.security_group_id
}

output "admin_secret_arn" {
  description = "The secret holding the Admin password."
  value       = aws_secretsmanager_secret.admin.arn
}
