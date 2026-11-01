output "arns" {
  description = "Tunnel document -> ARN: grant ssm:StartSession on it in the permission set of whoever may use it."
  value       = module.ssm_document.arns

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The tunnel files are not usable: ${join("; ", local.problems)}."
  }
}
