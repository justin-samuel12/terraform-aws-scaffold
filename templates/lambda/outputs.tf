output "arns" {
  description = "Function name -> ARN."
  value       = { for name, f in module.lambda_function : name => f.arn }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The function files are not usable: ${join("; ", local.problems)}."
  }
}
