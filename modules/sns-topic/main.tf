data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_sns_topic" "topic" {
  name                        = "${var.name}${local.suffix}"
  fifo_topic                  = var.fifo
  content_based_deduplication = var.fifo ? var.content_based_deduplication : null
  kms_master_key_id           = var.kms_key_arn

  tags = { Name = "${var.name}${local.suffix}" }
}

resource "aws_sns_topic_policy" "topic" {
  arn    = aws_sns_topic.topic.arn
  policy = jsonencode({ Version = "2012-10-17", Statement = local.statements })
}

resource "aws_sns_topic_subscription" "subscriptions" {
  for_each = var.subscriptions

  topic_arn            = aws_sns_topic.topic.arn
  protocol             = each.value.protocol
  endpoint             = each.value.endpoint
  raw_message_delivery = each.value.raw_message_delivery
  filter_policy        = each.value.filter_policy
  filter_policy_scope  = each.value.filter_policy_scope

  depends_on = [aws_lambda_permission.subscriptions]
}

# A Lambda subscriber must let this topic, and only this topic, invoke it before the subscription is made.
resource "aws_lambda_permission" "subscriptions" {
  for_each = { for key, s in var.subscriptions : key => s if s.protocol == "lambda" }

  statement_id  = "sns-${var.name}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.endpoint
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.topic.arn
}
