output "domain_name" {
  description = "The distribution's domain, for a Route 53 alias."
  value       = aws_cloudfront_distribution.distribution.domain_name
}

output "bucket_policy_statement" {
  description = "The statement the origin bucket's policy needs so this distribution, and only it, can read it."
  value = {
    Sid       = "CloudFront${replace(title(var.name), "-", "")}"
    Effect    = "Allow"
    Principal = { Service = "cloudfront.amazonaws.com" }
    Action    = "s3:GetObject"
    Resource  = "arn:aws:s3:::${var.origin_bucket.name}/*"
    Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.distribution.arn } }
  }
}
