output "domain_name" {
  description = "The distribution's domain, for a Route 53 alias."
  value       = aws_cloudfront_distribution.distribution.domain_name
}

output "bucket_policy_statement" {
  description = "The statement its origin buckets' policies need so this distribution, and only it, can read them."
  value = {
    Sid       = "CloudFront${replace(title(var.name), "-", "")}"
    Effect    = "Allow"
    Principal = { Service = "cloudfront.amazonaws.com" }
    Action    = "s3:GetObject"
    Resource  = [for o in var.origin : "arn:aws:s3:::${split(".s3.", o.domain_name)[0]}/*"]
    Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.distribution.arn } }
  }
}
