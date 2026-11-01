output "arns" {
  description = "Purpose -> key ARN in this region."
  value       = { for purpose, key in aws_kms_key.keys : purpose => key.arn }
}

output "replica_arns" {
  description = "<purpose>/<region> -> replica key ARN."
  value       = { for k, key in aws_kms_replica_key.replicas : k => key.arn }
}
