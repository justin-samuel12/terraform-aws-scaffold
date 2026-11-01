output "arn" {
  description = "The web ACL's ARN; a CloudFront distribution names it."
  value       = aws_wafv2_web_acl.web_acl.arn
}
