resource "aws_sns_topic" "topic" {
  name                        = var.name
  fifo_topic                  = var.fifo_topic
  content_based_deduplication = var.content_based_deduplication
  kms_master_key_id           = var.kms_key_arn

  tags = { Name = "${local.name_prefix}${local.short_name}" }
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
}
