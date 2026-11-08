output "plan_role_arn" {
  description = "The role pull-request plans and drift checks assume."
  value       = aws_iam_role.plan.arn
}

output "propose_role_arn" {
  description = "The role that plans from the protected branch and stores the plan for review."
  value       = aws_iam_role.propose.arn
}

output "apply_role_arns" {
  description = "Duty -> the role that applies an approved plan of that duty's stacks."
  value       = { for duty, role in aws_iam_role.apply : duty => role.arn }
}

output "network_role_arns" {
  description = "In the hub's account: environment -> the role its network stacks change the hub through."
  value       = { for env, role in aws_iam_role.network : env => role.arn }
}

output "boundary_arns" {
  description = "Duty -> the permission boundary every role its stacks create carries."
  value       = { for duty, p in aws_iam_policy.boundary : duty => p.arn }
}

output "oidc_provider_arn" {
  description = "The account's GitHub OIDC provider."
  value       = local.provider_arn
}

output "documents" {
  description = "Every policy's statements, for tests and static analysis."
  value       = module.policies.documents
}
