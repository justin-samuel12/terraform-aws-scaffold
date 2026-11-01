locals {
  config_dir = coalesce(var.config_dir, path.root)
  settings   = merge({ retention_days = 365 }, try(yamldecode(file("${local.config_dir}/logging.yml")), {}))

  # Named by account and region, so the names are unique and every stack can find them without reading this one's state.
  account_id = data.aws_caller_identity.current.account_id
  buckets = {
    load-balancer = "lb-logs-${local.account_id}-${var.region}"
    waf           = "aws-waf-logs-${local.account_id}-${var.region}"
  }
}
