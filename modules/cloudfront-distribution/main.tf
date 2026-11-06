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
  web_acl_id      = var.web_acl_id

  dynamic "origin" {
    for_each = var.origin
    content {
      origin_id                = origin.value.origin_id
      domain_name              = origin.value.domain_name
      origin_access_control_id = aws_cloudfront_origin_access_control.origin.id
    }
  }

  default_cache_behavior {
    target_origin_id           = var.default_cache_behavior.target_origin_id
    viewer_protocol_policy     = var.default_cache_behavior.viewer_protocol_policy
    allowed_methods            = var.default_cache_behavior.allowed_methods
    cached_methods             = var.default_cache_behavior.cached_methods
    compress                   = var.default_cache_behavior.compress
    cache_policy_id            = var.default_cache_behavior.cache_policy_id
    response_headers_policy_id = var.default_cache_behavior.response_headers_policy_id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.viewer_certificate.acm_certificate_arn
    ssl_support_method             = var.viewer_certificate.ssl_support_method
    minimum_protocol_version       = var.viewer_certificate.minimum_protocol_version
    cloudfront_default_certificate = var.viewer_certificate.cloudfront_default_certificate
  }

  tags = { Name = "${local.name_prefix}${var.name}" }

  lifecycle {
    precondition {
      condition     = length(var.aliases) == 0 || var.viewer_certificate.acm_certificate_arn != null
      error_message = "A distribution with aliases needs viewer_certificate.acm_certificate_arn."
    }
  }
}
