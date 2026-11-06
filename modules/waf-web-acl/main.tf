resource "aws_wafv2_web_acl" "web_acl" {
  name  = var.name
  scope = var.scope

  default_action {
    dynamic "allow" {
      for_each = var.default_action.allow == null ? [] : [1]
      content {}
    }

    dynamic "block" {
      for_each = var.default_action.block == null ? [] : [1]
      content {}
    }
  }

  dynamic "rule" {
    for_each = var.rule
    content {
      name     = rule.value.name
      priority = rule.value.priority

      dynamic "action" {
        for_each = rule.value.action == null ? [] : [rule.value.action]
        content {
          dynamic "allow" {
            for_each = action.value.allow == null ? [] : [1]
            content {}
          }

          dynamic "block" {
            for_each = action.value.block == null ? [] : [1]
            content {}
          }

          dynamic "count" {
            for_each = action.value.count == null ? [] : [1]
            content {}
          }
        }
      }

      dynamic "override_action" {
        for_each = rule.value.override_action == null ? [] : [rule.value.override_action]
        content {
          dynamic "none" {
            for_each = override_action.value.none == null ? [] : [1]
            content {}
          }

          dynamic "count" {
            for_each = override_action.value.count == null ? [] : [1]
            content {}
          }
        }
      }

      statement {
        dynamic "managed_rule_group_statement" {
          for_each = rule.value.statement.managed_rule_group_statement == null ? [] : [rule.value.statement.managed_rule_group_statement]
          content {
            name        = managed_rule_group_statement.value.name
            vendor_name = managed_rule_group_statement.value.vendor_name
          }
        }

        dynamic "rate_based_statement" {
          for_each = rule.value.statement.rate_based_statement == null ? [] : [rule.value.statement.rate_based_statement]
          content {
            limit              = rate_based_statement.value.limit
            aggregate_key_type = rate_based_statement.value.aggregate_key_type
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = rule.value.visibility_config.cloudwatch_metrics_enabled
        metric_name                = rule.value.visibility_config.metric_name
        sampled_requests_enabled   = rule.value.visibility_config.sampled_requests_enabled
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = var.visibility_config.cloudwatch_metrics_enabled
    metric_name                = var.visibility_config.metric_name
    sampled_requests_enabled   = var.visibility_config.sampled_requests_enabled
  }

  tags = { Name = "${local.name_prefix}${local.short_name}" }
}

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
  for_each = toset(var.resource_arns)

  resource_arn = each.key
  web_acl_arn  = aws_wafv2_web_acl.web_acl.arn
}
