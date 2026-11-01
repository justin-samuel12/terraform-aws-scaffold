data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

# The bucket stays private: only this distribution, signing its requests, may read it.
resource "aws_cloudfront_origin_access_control" "origin" {
  name                              = var.name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "distribution" {
  comment         = var.name
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.price_class
  aliases         = var.aliases
  web_acl_id      = var.web_acl_arn

  origin {
    origin_id                = var.origin_bucket.name
    domain_name              = var.origin_bucket.regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.origin.id
  }

  default_cache_behavior {
    target_origin_id           = var.origin_bucket.name
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = var.certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.certificate_arn == null ? null : "TLSv1.2_2021"
    cloudfront_default_certificate = var.certificate_arn == null
  }

  tags = { Name = var.name }

  lifecycle {
    precondition {
      condition     = length(var.aliases) == 0 || var.certificate_arn != null
      error_message = "A distribution with aliases needs certificate_arn."
    }
  }
}
