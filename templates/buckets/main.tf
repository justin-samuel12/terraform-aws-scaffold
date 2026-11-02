data "aws_caller_identity" "current" {}

# The environment's data key, from the keys stack, found by alias.
data "aws_kms_key" "data" {
  count = length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

module "s3_bucket" {
  source   = "../../modules/s3-bucket"
  for_each = { for name, f in local.files : name => f if length(local.names[name]) <= 63 }

  name            = local.names[each.key]
  kms_key_arn     = data.aws_kms_key.data[0].arn
  noncurrent_days = try(each.value.noncurrent_version_expiration.noncurrent_days, 90)
  expire_days     = try(each.value.expiration.days, null)
  backup          = try(each.value.backup, false)
  object_lock     = try({ mode = each.value.object_lock_configuration.default_retention.mode, days = each.value.object_lock_configuration.default_retention.days }, null)
  cors = [for c in try(each.value.cors_rule, []) : {
    allowed_methods = tolist(c.allowed_methods)
    allowed_origins = tolist(c.allowed_origins)
    allowed_headers = try(tolist(c.allowed_headers), [])
    max_age_seconds = try(c.max_age_seconds, 3000)
  }]
}
