output "arns" {
  description = "Role name -> ARN."
  value       = module.iam_role.arns

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The IAM files are not usable: ${join("; ", local.problems)}."
  }
}

output "instance_profiles" {
  description = "Instance profile name -> name, one per file in instance-profile/; compute finds them by name."
  value       = module.iam_role.instance_profiles
}

output "policy_arns" {
  description = "Customer-managed policy name -> ARN."
  value       = module.iam_role.policy_arns
}
