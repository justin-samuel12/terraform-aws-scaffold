output "endpoint" {
  description = "Where applications connect, host and port."
  value       = aws_db_instance.database.endpoint
}

output "port" {
  description = "The port applications connect on."
  value       = aws_db_instance.database.port
}

output "password_secret_arn" {
  description = "The Secrets Manager secret holding the admin password: RDS's own, or for RDS Custom the one made here."
  value       = local.custom ? aws_secretsmanager_secret.password[0].arn : try(aws_db_instance.database.master_user_secret[0].secret_arn, null)
}
