output "name" {
  description = "The bucket's name."
  value       = aws_s3_bucket.logs.id
}

output "arn" {
  description = "The bucket's ARN."
  value       = aws_s3_bucket.logs.arn
}
