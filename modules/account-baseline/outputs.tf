output "analyzer_arns" {
  description = "Region -> IAM Access Analyzer ARN."
  value       = { for region, analyzer in aws_accessanalyzer_analyzer.regions : region => analyzer.arn }
}
