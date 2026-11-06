data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "logs" {
  count = length(local.web_acls) > 0 ? 1 : 0

  bucket = "aws-waf-logs-${data.aws_caller_identity.current.account_id}-${var.region}"
}

data "aws_lb" "load_balancers" {
  for_each = local.load_balancer_lookups

  name = "${var.environment}-${each.key}"
}
