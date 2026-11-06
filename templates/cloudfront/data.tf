data "aws_s3_bucket" "origins" {
  for_each = local.bucket_lookups

  bucket = each.key
}

data "aws_acm_certificate" "certificates" {
  provider = aws.us_east_1
  for_each = local.certificate_lookups

  domain      = each.key
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_cloudfront_cache_policy" "policies" {
  for_each = local.cache_policy_lookups

  name = each.key
}

data "aws_cloudfront_response_headers_policy" "policies" {
  for_each = local.headers_lookups

  name = each.key
}
