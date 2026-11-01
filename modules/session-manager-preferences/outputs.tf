output "log_group" {
  description = "Where every session is logged."
  value       = aws_cloudwatch_log_group.sessions.name
}
