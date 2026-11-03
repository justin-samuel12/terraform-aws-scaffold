module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# The environment's messages key, from the keys stack, found by alias.
data "aws_kms_key" "messages" {
  count = length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-messages"
}

module "sqs_queue" {
  source   = "../../modules/sqs-queue"
  for_each = local.queues

  name                        = "${var.environment}-${each.key}"
  kms_key_arn                 = data.aws_kms_key.messages[0].arn
  fifo                        = try(each.value.fifo_queue, false)
  content_based_deduplication = try(each.value.content_based_deduplication, false)
  visibility_timeout_seconds  = try(each.value.visibility_timeout_seconds, 30)
  message_retention_seconds   = try(each.value.message_retention_seconds, 345600)
  delay_seconds               = try(each.value.delay_seconds, 0)
  receive_wait_time_seconds   = try(each.value.receive_wait_time_seconds, 20)
  max_receive_count           = try(each.value.dead_letter.max_receive_count, 5)
  topic_arns                  = local.delivering_topics[each.key]
  sender_accounts             = local.other_accounts[each.key].senders
  consumer_accounts           = local.other_accounts[each.key].consumers
}

module "sns_topic" {
  source   = "../../modules/sns-topic"
  for_each = local.topics

  name                        = "${var.environment}-${each.key}"
  kms_key_arn                 = data.aws_kms_key.messages[0].arn
  fifo                        = try(each.value.fifo_topic, false)
  content_based_deduplication = try(each.value.content_based_deduplication, false)
  subscriptions               = local.subscriptions[each.key]
  publisher_accounts          = local.other_accounts[each.key].publishers
  publisher_services          = local.publisher_services[each.key]

  # A queue must exist, and let the topic in, before the topic subscribes it.
  depends_on = [module.sqs_queue]
}
