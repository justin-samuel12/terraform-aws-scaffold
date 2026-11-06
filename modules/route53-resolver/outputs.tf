output "inbound_ips" {
  description = "The inbound endpoint's addresses, for HQ's DNS servers to forward AWS names to; empty without one."
  value       = flatten([for endpoint in aws_route53_resolver_endpoint.inbound : [for ip in endpoint.ip_address : ip.ip]])
}

output "rule_ids" {
  description = "Domain -> forwarding rule id; each environment's network associates these with its VPC."
  value       = merge({ for domain, rule in aws_route53_resolver_rule.forward : domain => rule.id }, { for domain, rule in aws_route53_resolver_rule.inbound : domain => rule.id })
}

output "rule_arns" {
  description = "Domain -> forwarding rule ARN, for sharing them with other accounts."
  value       = merge({ for domain, rule in aws_route53_resolver_rule.forward : domain => rule.arn }, { for domain, rule in aws_route53_resolver_rule.inbound : domain => rule.arn })
}
