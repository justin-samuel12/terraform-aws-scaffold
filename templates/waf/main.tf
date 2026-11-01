# The region's WAF log bucket, from the logging stack, and the load balancers by name: nothing reads another stack's state.
data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "logs" {
  count = length(local.web_acls) > 0 ? 1 : 0

  bucket = "aws-waf-logs-${data.aws_caller_identity.current.account_id}-${var.region}"
}

data "aws_lb" "load_balancers" {
  for_each = toset(flatten([for acl in local.web_acls : acl.load_balancers]))

  name = each.key
}

module "waf_web_acl" {
  source   = "../../modules/waf-web-acl"
  for_each = local.web_acls

  name           = each.key
  managed_rules  = coalesce(each.value.managed_rules, ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet", "AWSManagedRulesAmazonIpReputationList"])
  rate_limit     = each.value.rate_limit
  log_bucket_arn = data.aws_s3_bucket.logs[0].arn
  resource_arns  = [for lb in each.value.load_balancers : data.aws_lb.load_balancers[lb].arn]
}
