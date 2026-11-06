output "log_group" {
  description = "Where every session is logged, or null."
  value       = try(aws_cloudwatch_log_group.sessions[0].name, null)
}
