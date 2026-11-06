output "document_name" {
  description = "The SSM document that joins a Windows server, or null with no association."
  value       = local.enabled ? local.document_name : null
}

output "secret_arn" {
  description = "The join account's secret, which the servers' role may read, or null with no association."
  value       = local.enabled ? aws_secretsmanager_secret.join[0].arn : null
}

output "association_ids" {
  description = "Association name -> id."
  value       = { for name, a in aws_ssm_association.join : name => a.association_id }
}
