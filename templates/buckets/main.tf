module "s3_bucket" {
  source   = "../../modules/s3-bucket"
  for_each = { for name, b in local.buckets : name => b if length(local.problems) == 0 }

  name                      = local.names[each.key]
  kms_key_arn               = data.aws_kms_key.data[0].arn
  tags                      = each.value.tags
  object_lock_enabled       = each.value.object_lock_enabled
  object_lock_configuration = each.value.object_lock_configuration
  lifecycle_rule            = each.value.lifecycle_rule
  cors_rule                 = each.value.cors_rule
}
