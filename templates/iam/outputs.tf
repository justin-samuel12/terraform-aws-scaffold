output "arns" {
  description = "Role name -> ARN."
  value       = module.iam_role.arns
}

output "instance_profiles" {
  description = "Role name -> instance profile, for roles EC2 assumes; compute finds them by name."
  value       = module.iam_role.instance_profiles
}

output "policy_arns" {
  description = "Customer-managed policy name -> ARN."
  value       = module.iam_role.policy_arns
}
