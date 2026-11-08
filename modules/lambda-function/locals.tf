locals {
  has_rule        = var.schedule_expression != null || var.event_pattern != null
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "
  short_name      = trimprefix(var.name, "${local.environment_tag}-")

  queue = var.event_source_mapping == null ? [] : [var.event_source_mapping.event_source_arn]

  statements = concat(
    [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.function.arn}:*" }],
    [for s in var.statements : merge(
      { Effect = s.effect, Action = s.actions, Resource = s.resources },
      length(s.condition) == 0 ? {} : { Condition = { for test in distinct([for c in s.condition : c.test]) : test => { for c in s.condition : c.variable => c.values if c.test == test } } },
    )],
    [for arn in local.queue : { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"], Resource = arn }],
    [for arn in local.queue : { Effect = "Allow", Action = "kms:Decrypt", Resource = "*", Condition = { StringLike = { "kms:ViaService" = "sqs.*.amazonaws.com" } } }],
  )
}
