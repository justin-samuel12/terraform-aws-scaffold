resource "aws_wafv2_web_acl" "web_acl" {
  name  = var.name
  scope = var.scope

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = var.managed_rules
    content {
      name     = rule.value
      priority = rule.key + 1

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-${rule.value}"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.rate_limit == null ? [] : [var.rate_limit]
    content {
      name     = "rate-limit"
      priority = 0

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = rule.value
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = { Name = var.name }
}

# Every request is logged, without the Authorization and Cookie headers.
resource "aws_wafv2_web_acl_logging_configuration" "web_acl" {
  resource_arn            = aws_wafv2_web_acl.web_acl.arn
  log_destination_configs = [var.log_bucket_arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

resource "aws_wafv2_web_acl_association" "resources" {
  for_each = var.scope == "REGIONAL" ? toset(var.resource_arns) : toset([])

  resource_arn = each.key
  web_acl_arn  = aws_wafv2_web_acl.web_acl.arn
}
