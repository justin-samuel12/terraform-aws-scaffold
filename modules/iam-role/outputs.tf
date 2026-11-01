output "arns" {
  description = "Role name -> ARN."
  value       = { for name, role in aws_iam_role.roles : name => role.arn }

  # A role is handed out only once its permissions are attached: RDS, for one, checks them when it is given the role.
  depends_on = [aws_iam_role_policy_attachment.managed, aws_iam_role_policy_attachment.policies, aws_iam_role_policy.own]
}

output "instance_profiles" {
  description = "Role name -> instance profile name, for roles EC2 assumes."
  value       = { for name, profile in aws_iam_instance_profile.profiles : name => profile.name }

  depends_on = [aws_iam_role_policy_attachment.managed, aws_iam_role_policy_attachment.policies, aws_iam_role_policy.own]
}

output "policy_arns" {
  description = "Customer-managed policy name -> ARN."
  value       = { for name, p in aws_iam_policy.policies : name => p.arn }
}
