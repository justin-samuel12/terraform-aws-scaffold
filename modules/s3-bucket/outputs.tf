output "name" {
  description = "The bucket's name."
  value       = aws_s3_bucket.bucket.id
}

output "arn" {
  description = "The bucket's ARN."
  value       = aws_s3_bucket.bucket.arn
}

output "regional_domain_name" {
  description = "For a CloudFront origin."
  value       = aws_s3_bucket.bucket.bucket_regional_domain_name
}
