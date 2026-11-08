output "role_boundary" {
  description = "The IAM path and permission boundary every role this stack creates carries: /deployed/ and terraform-boundary-<environment>-<duty>. null where the provider has no Environment and Component tags, as in a module's own tests."
  value = local.environment == "" || local.component == "" ? null : {
    path                 = local.path
    permissions_boundary = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/terraform-boundary-${local.environment}-${local.duty}"
  }

  precondition {
    condition     = local.component == "" || length(local.owners) == 1
    error_message = "templates/duties.yml must name exactly one duty for the ${local.component} component; ${length(local.owners) == 0 ? "none does" : "${join(" and ", local.owners)} both do"}. The duty decides which pipeline role deploys it and which boundary its roles carry."
  }
}

output "duty" {
  description = "The duty that deploys this stack."
  value       = local.duty
}
