resource "aws_iam_role" "function" {
  name = "lambda-${var.name}-${data.aws_region.current.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Name = "${local.name_prefix}${local.short_name}" }
}

resource "aws_iam_role_policy" "function" {
  name   = "lambda-${var.name}"
  role   = aws_iam_role.function.id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.statements })
}

resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.retention_in_days

  tags = { Name = "${local.name_prefix}${local.short_name}" }
}

resource "aws_lambda_function" "function" {
  function_name    = var.name
  role             = aws_iam_role.function.arn
  runtime          = var.runtime
  handler          = var.handler
  architectures    = ["arm64"]
  memory_size      = var.memory_size
  timeout          = var.timeout
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256

  dynamic "environment" {
    for_each = length(var.environment) > 0 ? [var.environment] : []
    content {
      variables = environment.value
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.function.name
  }

  tags = { Name = "${local.name_prefix}${local.short_name}" }

  depends_on = [aws_iam_role_policy.function]
}

resource "aws_cloudwatch_event_rule" "schedule" {
  count = var.schedule_expression == null ? 0 : 1

  name                = "lambda-${var.name}"
  schedule_expression = var.schedule_expression

  tags = { Name = "${local.name_prefix}${local.short_name}" }
}

resource "aws_cloudwatch_event_target" "schedule" {
  count = var.schedule_expression == null ? 0 : 1

  rule = aws_cloudwatch_event_rule.schedule[0].name
  arn  = aws_lambda_function.function.arn

  depends_on = [aws_lambda_permission.schedule]
}

resource "aws_lambda_permission" "schedule" {
  count = var.schedule_expression == null ? 0 : 1

  statement_id  = "schedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[0].arn
}

resource "aws_lambda_event_source_mapping" "queue" {
  count = var.event_source_mapping == null ? 0 : 1

  event_source_arn                   = var.event_source_mapping.event_source_arn
  function_name                      = aws_lambda_function.function.arn
  batch_size                         = var.event_source_mapping.batch_size
  maximum_batching_window_in_seconds = var.event_source_mapping.maximum_batching_window_in_seconds
  function_response_types            = var.event_source_mapping.function_response_types

  tags = { Name = "${local.name_prefix}${local.short_name}" }

  depends_on = [aws_iam_role_policy.function]
}

resource "aws_lambda_permission" "topics" {
  for_each = var.topics

  statement_id  = "sns-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = each.value.arn
}

resource "aws_sns_topic_subscription" "topics" {
  for_each = var.topics

  topic_arn           = each.value.arn
  protocol            = "lambda"
  endpoint            = aws_lambda_function.function.arn
  filter_policy       = each.value.filter_policy
  filter_policy_scope = each.value.filter_policy_scope

  depends_on = [aws_lambda_permission.topics]
}
