data "aws_partition" "current" {}

# Messages that keep failing land here, kept the full 14 days, instead of being retried forever or lost.
resource "aws_sqs_queue" "dead_letter" {
  name                              = "${var.name}-dlq${local.suffix}"
  fifo_queue                        = var.fifo
  message_retention_seconds         = 1209600
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = { Name = "${var.name}-dlq${local.suffix}" }
}

resource "aws_sqs_queue" "queue" {
  name                              = "${var.name}${local.suffix}"
  fifo_queue                        = var.fifo
  content_based_deduplication       = var.fifo ? var.content_based_deduplication : null
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  message_retention_seconds         = var.message_retention_seconds
  delay_seconds                     = var.delay_seconds
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = { Name = "${var.name}${local.suffix}" }
}

# Only this queue may use the dead-letter queue as its own.
resource "aws_sqs_queue_redrive_allow_policy" "dead_letter" {
  queue_url = aws_sqs_queue.dead_letter.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.queue.arn]
  })
}

resource "aws_sqs_queue_policy" "queue" {
  queue_url = aws_sqs_queue.queue.id
  policy    = jsonencode({ Version = "2012-10-17", Statement = local.queue_statements })
}

resource "aws_sqs_queue_policy" "dead_letter" {
  queue_url = aws_sqs_queue.dead_letter.id
  policy    = jsonencode({ Version = "2012-10-17", Statement = [local.deny_insecure_transport[1]] })
}
