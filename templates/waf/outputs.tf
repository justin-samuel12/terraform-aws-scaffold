output "arns" {
  description = "Web ACL name -> ARN."
  value       = { for name, acl in module.waf_web_acl : name => acl.arn }
}
