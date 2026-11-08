output "plan_role_arn" {
  description = "The role pull-request plans and drift checks assume in this environment's account."
  value       = try(module.pipeline_roles[0].plan_role_arn, null)

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The pipeline settings are not usable: ${join("; ", local.problems)}."
  }
}

output "propose_role_arn" {
  description = "The role that plans from the protected branch and stores the plan for review."
  value       = try(module.pipeline_roles[0].propose_role_arn, null)
}

output "apply_role_arns" {
  description = "Duty -> the role that applies an approved plan of that duty's stacks in this environment."
  value       = try(module.pipeline_roles[0].apply_role_arns, {})
}

output "network_role_arns" {
  description = "Only for shared: environment -> the role its network stacks change the hub through."
  value       = try(module.pipeline_roles[0].network_role_arns, {})
}

output "boundary_arns" {
  description = "Duty -> the permission boundary every role its stacks create must carry."
  value       = try(module.pipeline_roles[0].boundary_arns, {})
}

output "creates_oidc_provider" {
  description = "Whether this stack owns its account's GitHub OIDC provider: the first environment in the account, shared first, does."
  value       = local.create_oidc_provider
}

output "duties" {
  description = "The duties this environment deploys, each with its own apply role."
  value       = sort(keys(local.duties))
}
