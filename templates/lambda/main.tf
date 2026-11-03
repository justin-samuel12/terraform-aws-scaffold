# Queues a function takes messages from, from the messaging stack, found by name.
data "aws_sqs_queue" "queues" {
  for_each = local.queue_names

  name = each.value
}

module "lambda_function" {
  source   = "../../modules/lambda-function"
  for_each = { for name, f in local.files : name => f if length(fileset("${local.config_dir}/src/${name}", "**")) > 0 }

  name               = "${var.environment}-${each.key}"
  source_dir         = "${local.config_dir}/src/${each.key}"
  runtime            = each.value.runtime
  handler            = each.value.handler
  memory             = try(each.value.memory_size, 256)
  timeout            = try(each.value.timeout, 30)
  environment        = { for k, v in try(each.value.environment.variables, {}) : k => tostring(v) }
  statements         = [for s in try(each.value.statement, []) : { actions = tolist(s.actions), resources = tolist(s.resources) }]
  schedule           = try(each.value.schedule_expression, null)
  log_retention_days = try(each.value.retention_in_days, 365)
  queue = can(each.value.event_source_mapping.event_source_arn) ? {
    arn                                = contains(keys(local.queue_names), each.key) ? data.aws_sqs_queue.queues[each.key].arn : each.value.event_source_mapping.event_source_arn
    batch_size                         = try(each.value.event_source_mapping.batch_size, 10)
    maximum_batching_window_in_seconds = try(each.value.event_source_mapping.maximum_batching_window_in_seconds, 0)
  } : null
}
