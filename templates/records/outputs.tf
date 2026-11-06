output "names" {
  description = "Record file -> the full name."
  value       = merge(module.route53_record.names, module.own_records.names)

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The record files are not usable: ${join("; ", local.problems)}."
  }
}
