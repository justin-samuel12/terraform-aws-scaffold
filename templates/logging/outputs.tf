output "buckets" {
  description = "What delivers to it -> bucket name."
  value       = { for kind, bucket in module.log_bucket : kind => bucket.name }
}
