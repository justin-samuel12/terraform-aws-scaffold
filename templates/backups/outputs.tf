output "vaults" {
  description = "Vault name -> its ARN."
  value       = module.backup_plan.vaults

  precondition {
    condition     = local.ready
    error_message = "The backup files are not usable: ${join("; ", local.problems)}."
  }
}

output "plans" {
  description = "Plan name -> its ID."
  value       = module.backup_plan.plans
}
