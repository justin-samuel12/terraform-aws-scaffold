output "endpoint" {
  description = "Where applications connect, host and port."
  value       = aws_db_instance.database.endpoint
}

output "password_secret_arn" {
  description = "The Secrets Manager secret RDS keeps the admin password in."
  value       = try(aws_db_instance.database.master_user_secret[0].secret_arn, null)
}
