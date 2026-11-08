output "policies" {
  description = "Policy name -> its JSON document, for static analysis."
  value       = module.policies.policies
}
