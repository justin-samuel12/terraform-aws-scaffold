module "waf_web_acl" {
  source   = "../../modules/waf-web-acl"
  for_each = { for name, acl in local.web_acls : name => acl if length(local.problems) == 0 }

  name              = "${var.environment}-${each.key}"
  scope             = var.scope
  default_action    = each.value.default_action
  rule              = each.value.rule
  visibility_config = each.value.visibility_config
  log_bucket_arn    = data.aws_s3_bucket.logs[0].arn
  resource_arns     = local.resource_arns[each.key]
}
