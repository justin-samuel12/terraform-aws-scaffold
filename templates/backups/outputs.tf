output "vault" {
  description = "The environment's backup vault."
  value       = module.backup_plan.vault
}

output "copy_region" {
  description = "Where backups are copied, or null."
  value       = local.copy_region
}
