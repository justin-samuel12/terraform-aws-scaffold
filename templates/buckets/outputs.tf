output "buckets" {
  description = "File name -> bucket name."
  value       = { for name, b in module.s3_bucket : name => b.name }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The bucket files are not usable: ${join("; ", local.problems)}."
  }
}
