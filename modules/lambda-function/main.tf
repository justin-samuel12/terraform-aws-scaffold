resource "aws_iam_role" "function" {
  name                 = "lambda-${var.name}-${data.aws_region.current.region}"
  path                 = try(var.role_boundary.path, "/")
  permissions_boundary = try(var.role_boundary.permissions_boundary, null)

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

resource "aws_iam_role_policy_attachment" "vpc" {
  count = var.vpc_config == null ? 0 : 1

  role       = aws_iam_role.function.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
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
  architectures    = var.architectures
  memory_size      = var.memory_size
  timeout          = var.timeout
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  layers           = var.layers

  dynamic "vpc_config" {
    for_each = var.vpc_config == null ? [] : [var.vpc_config]
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

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

  depends_on = [aws_iam_role_policy.function, aws_iam_role_policy_attachment.vpc]
}

resource "aws_cloudwatch_event_rule" "rule" {
  count = local.has_rule ? 1 : 0

  name                = "lambda-${var.name}"
  schedule_expression = var.schedule_expression
  event_pattern       = var.event_pattern

  tags = { Name = "${local.name_prefix}${local.short_name}" }
}

resource "aws_cloudwatch_event_target" "rule" {
  count = local.has_rule ? 1 : 0

  rule = aws_cloudwatch_event_rule.rule[0].name
  arn  = aws_lambda_function.function.arn

  depends_on = [aws_lambda_permission.rule]
}

resource "aws_lambda_permission" "rule" {
  count = local.has_rule ? 1 : 0

  statement_id  = "rule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rule[0].arn
}

resource "aws_lambda_event_source_mapping" "queue" {
  count = var.event_source_mapping == null ? 0 : 1

  event_source_arn                   = var.event_source_mapping.event_source_arn
  function_name                      = aws_lambda_function.function.arn
  batch_size                         = var.event_source_mapping.batch_size
  maximum_batching_window_in_seconds = var.event_source_mapping.maximum_batching_window_in_seconds
  function_response_types            = var.event_source_mapping.function_response_types

  tags = { Name = "${local.name_prefix}${local.short_name}" }

  depends_on = [aws_iam_role_policy.function, aws_iam_role_policy_attachment.vpc]
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
