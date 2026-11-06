module "log_bucket" {
  source   = "../../modules/log-bucket"
  for_each = local.ready ? local.buckets : {}

  name     = each.value.bucket
  delivers = each.value.delivers
  tags     = each.value.tags
  rule     = each.value.rule
}
