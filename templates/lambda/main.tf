module "lambda_function" {
  source   = "../../modules/lambda-function"
  for_each = { for name, f in local.files : name => f if length(local.problems) == 0 }

  name                = "${var.environment}-${each.key}"
  source_dir          = "${local.config_dir}/src/${each.key}"
  runtime             = each.value.runtime
  handler             = each.value.handler
  memory_size         = try(tonumber(each.value.memory_size), null)
  timeout             = try(tonumber(each.value.timeout), null)
  environment         = { for k, v in try(each.value.environment.variables, {}) : k => tostring(v) }
  statements          = local.statements[each.key]
  schedule_expression = try(tostring(each.value.cloudwatch_event_rule.schedule_expression), null)
  retention_in_days   = tonumber(each.value.cloudwatch_log_group.retention_in_days)
  event_source_mapping = can(each.value.event_source_mapping) ? {
    event_source_arn                   = contains(keys(local.queue_names), each.key) ? data.aws_sqs_queue.queues[each.key].arn : tostring(each.value.event_source_mapping.event_source_arn)
    batch_size                         = try(tonumber(each.value.event_source_mapping.batch_size), null)
    maximum_batching_window_in_seconds = try(tonumber(each.value.event_source_mapping.maximum_batching_window_in_seconds), null)
    function_response_types            = try([for t in concat(each.value.event_source_mapping.function_response_types, []) : tostring(t)], null)
  } : null
  topics = {
    for key, s in local.subscriptions[each.key] : key => {
      arn                 = s.topic != null ? data.aws_sns_topic.topics[s.topic].arn : s.arn
      filter_policy       = s.filter_policy
      filter_policy_scope = s.filter_policy_scope
    }
  }
}
