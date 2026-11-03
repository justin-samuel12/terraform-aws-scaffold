output "endpoint" {
  description = "Where applications write, host and port: always the current writer."
  value       = "${aws_rds_cluster.cluster.endpoint}:${local.port}"
}

output "reader_endpoint" {
  description = "Where applications only read, host and port: spread across the readers."
  value       = "${aws_rds_cluster.cluster.reader_endpoint}:${local.port}"
}

output "port" {
  description = "The port applications connect on."
  value       = local.port
}

output "password_secret_arn" {
  description = "The Secrets Manager secret RDS keeps the admin password in."
  value       = try(aws_rds_cluster.cluster.master_user_secret[0].secret_arn, null)
}
