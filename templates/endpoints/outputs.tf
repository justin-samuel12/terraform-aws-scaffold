output "ids" {
  description = "Service -> endpoint id."
  value       = module.vpc_endpoint.ids

  precondition {
    condition     = length(local.problems) == 0
    error_message = "endpoints.yml is not usable: ${join("; ", local.problems)}."
  }
}
