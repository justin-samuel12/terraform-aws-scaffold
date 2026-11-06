resource "aws_sqs_queue" "queues" {
  for_each = var.queues

  name                        = each.key
  fifo_queue                  = each.value.fifo_queue
  content_based_deduplication = each.value.content_based_deduplication
  visibility_timeout_seconds  = each.value.visibility_timeout_seconds
  message_retention_seconds   = each.value.message_retention_seconds
  delay_seconds               = each.value.delay_seconds
  receive_wait_time_seconds   = each.value.receive_wait_time_seconds
  kms_master_key_id           = var.kms_key_arn

  tags = { Name = "${local.name_prefix}${trimprefix(each.key, "${local.environment_tag}-")}" }
}

resource "aws_sqs_queue_redrive_policy" "queues" {
  for_each = local.redriven

  queue_url = aws_sqs_queue.queues[each.key].id
  redrive_policy = jsonencode({
    deadLetterTargetArn = each.value.redrive_policy.dead_letter_target_arn
    maxReceiveCount     = each.value.redrive_policy.max_receive_count
  })

  depends_on = [aws_sqs_queue.queues]
}

resource "aws_sqs_queue_redrive_allow_policy" "queues" {
  for_each = local.allowing

  queue_url = aws_sqs_queue.queues[each.key].id
  redrive_allow_policy = jsonencode(merge(
    { redrivePermission = each.value.redrive_allow_policy.redrive_permission },
    each.value.redrive_allow_policy.source_queue_arns == null ? {} : { sourceQueueArns = each.value.redrive_allow_policy.source_queue_arns },
  ))

  depends_on = [aws_sqs_queue.queues]
}

resource "aws_sqs_queue_policy" "queues" {
  for_each = var.queues

  queue_url = aws_sqs_queue.queues[each.key].id
  policy    = jsonencode({ Version = "2012-10-17", Statement = local.policies[each.key] })
}
