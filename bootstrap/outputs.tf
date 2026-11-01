output "bucket" {
  description = "The state bucket, for state.bucket in config/global.yml."
  value       = aws_s3_bucket.state.id
}

output "replica" {
  description = "The replica bucket, or null without a replica region."
  value       = try(aws_s3_bucket.replica[0].id, null)
}
