output "urls" {
  description = "Repository name -> URL."
  value       = module.ecr_repository.urls

  precondition {
    condition     = local.ready
    error_message = "The ecr files are not usable: ${join("; ", local.problems)}."
  }
}
