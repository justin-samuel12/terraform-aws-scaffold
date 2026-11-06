output "arns" {
  description = "Web ACL name -> ARN."
  value       = { for name, acl in module.waf_web_acl : name => acl.arn }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The web ACL files are not usable: ${join("; ", local.problems)}."
  }
}
