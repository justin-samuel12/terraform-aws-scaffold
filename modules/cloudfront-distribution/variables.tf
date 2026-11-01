variable "name" {
  description = "The distribution's name: its comment and the origin access control's name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,63}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens."
  }
}

variable "aliases" {
  description = "The domains it answers on; each needs certificate_arn to cover it."
  type        = list(string)
  default     = []
}

variable "origin_bucket" {
  description = "The private S3 bucket it serves: its regional domain name and its name."
  type = object({
    name                 = string
    regional_domain_name = string
  })
}

variable "certificate_arn" {
  description = "An ACM certificate in us-east-1 covering every alias."
  type        = string
  default     = null

  validation {
    condition     = var.certificate_arn == null || can(regex("^arn:aws[a-z-]*:acm:us-east-1:", var.certificate_arn))
    error_message = "CloudFront uses certificates from us-east-1 only."
  }
}

variable "web_acl_arn" {
  description = "A CLOUDFRONT-scoped web ACL, or null."
  type        = string
  default     = null
}

variable "price_class" {
  description = "Which edge locations serve it: PriceClass_100 (North America and Europe), PriceClass_200, PriceClass_All."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}
