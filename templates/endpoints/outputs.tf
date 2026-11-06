output "ids" {
  description = "Endpoint name -> endpoint id."
  value       = module.vpc_endpoint.ids

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The endpoint files are not usable: ${join("; ", local.problems)}."
  }
}
