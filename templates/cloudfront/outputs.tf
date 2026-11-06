output "distributions" {
  description = "Distribution name -> its domain, and the statement its origin buckets' policies need."
  value       = { for name, d in module.cloudfront_distribution : name => { domain_name = d.domain_name, bucket_policy_statement = d.bucket_policy_statement } }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The distribution files are not usable: ${join("; ", local.problems)}."
  }
}

output "web_acls" {
  description = "Web ACL name -> ARN, for the distributions' web_acl_id."
  value       = module.web_acls.arns
}
