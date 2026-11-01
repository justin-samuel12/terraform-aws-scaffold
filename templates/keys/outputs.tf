output "arns" {
  description = "Purpose -> key ARN; other stacks find keys by alias, alias/<environment>-<purpose>."
  value       = module.kms_key.arns
}
