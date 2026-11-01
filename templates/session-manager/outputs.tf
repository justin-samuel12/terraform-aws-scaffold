output "log_group" {
  description = "Where every session in the region is logged."
  value       = module.session_manager_preferences.log_group
}
