output "names" {
  description = "Record file -> the full name."
  value       = module.route53_record.names

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The record files are not usable: ${join("; ", local.problems)}."
  }
}
