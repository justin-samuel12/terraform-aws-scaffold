module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "sqs_queue" {
  source = "../../modules/sqs-queue"

  kms_key_arn = try(data.aws_kms_key.messages[0].arn, "")
  queues      = { for name, q in local.sqs_queues : name => q if length(local.problems) == 0 }
}

module "sns_topic" {
  source   = "../../modules/sns-topic"
  for_each = { for name, f in local.topics : name => f if length(local.problems) == 0 }

  name                        = local.topic_names[each.key]
  kms_key_arn                 = data.aws_kms_key.messages[0].arn
  fifo_topic                  = try(tobool(each.value.fifo_topic), null)
  content_based_deduplication = try(tobool(each.value.content_based_deduplication), null)
  policy_statements           = local.statements.topic[each.key]
  subscriptions               = local.subscriptions[each.key]

  depends_on = [module.sqs_queue]
}
