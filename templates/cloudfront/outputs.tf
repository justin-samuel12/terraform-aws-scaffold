output "distributions" {
  description = "Distribution name -> its domain, and the statement its origin bucket's policy needs."
  value       = { for name, d in module.cloudfront_distribution : name => { domain_name = d.domain_name, bucket_policy_statement = d.bucket_policy_statement } }
}
