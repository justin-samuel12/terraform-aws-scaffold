variable "name" {
  description = "The distribution's name: its comment and the origin access control's name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,63}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens."
  }
}

variable "aliases" {
  description = "The domains it answers on; viewer_certificate's acm_certificate_arn must cover each."
  type        = list(string)
  default     = []
}

variable "origin" {
  description = "aws_cloudfront_distribution's origin blocks: private S3 buckets, each an origin_id and the bucket's regional domain_name. Every origin is reached through this distribution's origin access control."
  type = list(object({
    origin_id   = string
    domain_name = string
  }))

  validation {
    condition     = length(var.origin) > 0 && length(distinct([for o in var.origin : o.origin_id])) == length(var.origin)
    error_message = "A distribution has at least one origin, each with its own origin_id."
  }
}

variable "default_cache_behavior" {
  description = "aws_cloudfront_distribution's default_cache_behavior."
  type = object({
    target_origin_id           = string
    viewer_protocol_policy     = string
    allowed_methods            = list(string)
    cached_methods             = list(string)
    compress                   = bool
    cache_policy_id            = string
    response_headers_policy_id = optional(string)
  })

  validation {
    condition     = contains(["redirect-to-https", "https-only"], var.default_cache_behavior.viewer_protocol_policy)
    error_message = "viewer_protocol_policy is redirect-to-https or https-only: viewers never get plain HTTP."
  }

  validation {
    condition     = contains([for o in var.origin : o.origin_id], var.default_cache_behavior.target_origin_id)
    error_message = "target_origin_id is the origin_id of one of the distribution's origins."
  }
}

variable "price_class" {
  description = "Which edge locations serve it: PriceClass_100 (North America and Europe), PriceClass_200, PriceClass_All."
  type        = string

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "viewer_certificate" {
  description = "aws_cloudfront_distribution's viewer_certificate: an ACM certificate in us-east-1 with ssl_support_method and minimum_protocol_version, or cloudfront_default_certificate = true for a distribution without aliases."
  type = object({
    acm_certificate_arn            = optional(string)
    ssl_support_method             = optional(string)
    minimum_protocol_version       = optional(string)
    cloudfront_default_certificate = optional(bool)
  })

  validation {
    condition     = var.viewer_certificate.acm_certificate_arn == null || can(regex("^arn:aws[a-z-]*:acm:us-east-1:", coalesce(var.viewer_certificate.acm_certificate_arn, "-")))
    error_message = "CloudFront uses certificates from us-east-1 only."
  }

  validation {
    condition = (var.viewer_certificate.acm_certificate_arn != null
      ? (var.viewer_certificate.cloudfront_default_certificate != true && contains(["sni-only", "vip"], coalesce(var.viewer_certificate.ssl_support_method, "-")) && contains(["TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021", "TLSv1.2_2025", "TLSv1.3_2025"], coalesce(var.viewer_certificate.minimum_protocol_version, "-")))
    : (var.viewer_certificate.cloudfront_default_certificate == true && var.viewer_certificate.ssl_support_method == null && var.viewer_certificate.minimum_protocol_version == null))
    error_message = "viewer_certificate is acm_certificate_arn with ssl_support_method (sni-only or vip) and a minimum_protocol_version of TLS 1.2 or later, or cloudfront_default_certificate: true alone."
  }
}

variable "web_acl_id" {
  description = "The ARN of a CLOUDFRONT-scoped web ACL, or null."
  type        = string
  default     = null
}
