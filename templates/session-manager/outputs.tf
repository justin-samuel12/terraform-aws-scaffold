output "log_group" {
  description = "Where every session in the region is logged, or null."
  value       = module.session_manager_preferences.log_group

  precondition {
    condition     = local.ready
    error_message = "The session-manager files are not usable: ${join("; ", local.problems)}."
  }
}
