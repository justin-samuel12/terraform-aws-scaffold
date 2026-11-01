data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "origins" {
  for_each = toset([for d in local.distributions : d.origin_bucket])

  bucket = each.key
}

# Certificates and CLOUDFRONT web ACLs live only in us-east-1.
data "aws_acm_certificate" "certificates" {
  provider = aws.us_east_1
  for_each = toset(compact([for d in local.distributions : d.certificate]))

  domain      = each.key
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_s3_bucket" "waf_logs" {
  provider = aws.us_east_1
  count    = anytrue([for d in local.distributions : d.waf]) ? 1 : 0

  bucket = "aws-waf-logs-${local.account_id}-us-east-1"
}

module "waf_web_acl" {
  source    = "../../modules/waf-web-acl"
  for_each  = { for name, d in local.distributions : name => d if d.waf }
  providers = { aws = aws.us_east_1 }

  name           = "cloudfront-${each.key}"
  scope          = "CLOUDFRONT"
  log_bucket_arn = data.aws_s3_bucket.waf_logs[0].arn
}

module "cloudfront_distribution" {
  source   = "../../modules/cloudfront-distribution"
  for_each = local.distributions

  name            = each.key
  aliases         = each.value.aliases
  origin_bucket   = { name = each.value.origin_bucket, regional_domain_name = data.aws_s3_bucket.origins[each.value.origin_bucket].bucket_regional_domain_name }
  certificate_arn = each.value.certificate == null ? null : data.aws_acm_certificate.certificates[each.value.certificate].arn
  web_acl_arn     = each.value.waf ? module.waf_web_acl[each.key].arn : null
  price_class     = each.value.price_class
}
