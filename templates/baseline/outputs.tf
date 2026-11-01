output "regions" {
  description = "The regions the baseline covers."
  value       = local.regions
}

output "analyzer_arns" {
  description = "Region -> IAM Access Analyzer ARN."
  value       = module.account_baseline.analyzer_arns
}
