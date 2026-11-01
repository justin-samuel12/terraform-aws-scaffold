data "aws_caller_identity" "current" {}

module "log_bucket" {
  source   = "../../modules/log-bucket"
  for_each = local.buckets

  name           = each.value
  delivers       = each.key
  retention_days = local.settings.retention_days
}
