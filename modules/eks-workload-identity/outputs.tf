output "arns" {
  description = "Role name -> ARN, for Vault's AWS auth roles to bind to."
  value       = { for name, role in aws_iam_role.roles : name => role.arn }

  depends_on = [aws_iam_role_policy_attachment.managed, aws_iam_role_policy.own]
}

output "associations" {
  description = "Role name -> the namespace and service account whose pods get it."
  value       = { for name, a in aws_eks_pod_identity_association.associations : name => { namespace = a.namespace, service_account = a.service_account } }
}
