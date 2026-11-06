output "vaults" {
  description = "Vault name -> its ARN."
  value       = { for name, v in aws_backup_vault.vaults : name => v.arn }
}

output "plans" {
  description = "Plan name -> its ID."
  value       = { for name, p in aws_backup_plan.plans : name => p.id }
}
