output "names" {
  description = "Record key -> the full name."
  value       = { for k, r in aws_route53_record.records : k => r.fqdn }
}
