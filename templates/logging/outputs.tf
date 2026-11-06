output "buckets" {
  description = "File name -> bucket name."
  value       = { for name, bucket in module.log_bucket : name => bucket.name }

  precondition {
    condition     = local.ready
    error_message = "The log bucket files are not usable: ${join("; ", local.problems)}."
  }
}
