output "arns" {
  description = "Document name -> ARN."
  value       = module.ssm_document.arns

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The document files are not usable: ${join("; ", local.problems)}."
  }
}
