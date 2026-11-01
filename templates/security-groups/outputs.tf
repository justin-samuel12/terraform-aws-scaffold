output "ids" {
  description = "Group name -> security group id."
  value       = module.security_group.ids

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The group files are not usable: ${join("; ", local.problems)}."
  }
}
