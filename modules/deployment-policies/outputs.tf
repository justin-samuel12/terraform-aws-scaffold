output "documents" {
  description = "Policy name -> its statements, as HCL objects, for tests and static analysis: read, plan, propose, <duty>, <duty>-limits, <duty>-environment, <duty>-ownership, boundary-<duty>, and network-role for a spoke."
  value       = local.documents
}

output "policies" {
  description = "Policy name -> its JSON policy document, as IAM takes it."
  value       = { for name, statements in local.documents : name => jsonencode({ Version = "2012-10-17", Statement = statements }) }
}

output "trust" {
  description = "plan, propose and apply -> the JSON trust policy of that kind of pipeline role: the GitHub subjects that may assume it."
  value       = { for kind, document in local.trust : kind => jsonencode(document) }
}

output "network_trust" {
  description = "The JSON trust policy of terraform-network-<environment> in the hub account: only the environment's network apply role assumes it."
  value       = jsonencode(local.network_trust)
}

output "dns_read_trust" {
  description = "The JSON trust policy of terraform-dns-read-<environment> in the hub account: only the environment's plan and propose roles assume it."
  value       = jsonencode(local.dns_read_trust)
}

output "boundary_arns" {
  description = "Duty -> the ARN of the permission boundary every role that duty's stacks create must carry."
  value       = local.boundary_arn
}

output "role_path" {
  description = "The IAM path every role, instance profile and policy that a stack creates is under; the pipeline may pass and manage only those."
  value       = local.role_path
}
