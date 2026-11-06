module "web_acls" {
  source    = "../waf"
  providers = { aws = aws.us_east_1 }

  environment = "cloudfront"
  region      = "us-east-1"
  scope       = "CLOUDFRONT"
  config_dir  = "${local.config_dir}/web-acl"
}

module "cloudfront_distribution" {
  source   = "../../modules/cloudfront-distribution"
  for_each = { for name, d in local.resolved : name => d if length(local.problems) == 0 }

  name                   = each.key
  aliases                = each.value.aliases
  origin                 = each.value.origin
  default_cache_behavior = each.value.default_cache_behavior
  price_class            = each.value.price_class
  viewer_certificate     = each.value.viewer_certificate
  web_acl_id             = each.value.web_acl_id
}
