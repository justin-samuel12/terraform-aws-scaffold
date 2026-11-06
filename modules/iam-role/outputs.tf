output "arns" {
  description = "Role name -> ARN."
  value       = { for name, role in aws_iam_role.roles : name => role.arn }

  depends_on = [aws_iam_role_policy_attachment.managed, aws_iam_role_policy_attachment.policies, aws_iam_role_policy.own]
}

output "instance_profiles" {
  description = "Instance profile name -> its name; without instance_profiles, keyed by the role, of the same name, for every role EC2 assumes."
  value       = { for name, profile in aws_iam_instance_profile.profiles : name => profile.name }

  depends_on = [aws_iam_role_policy_attachment.managed, aws_iam_role_policy_attachment.policies, aws_iam_role_policy.own]
}

output "policy_arns" {
  description = "Customer-managed policy name -> ARN."
  value       = { for name, p in aws_iam_policy.policies : name => p.arn }
}
