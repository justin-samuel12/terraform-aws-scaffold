data "aws_sqs_queue" "queues" {
  for_each = { for name, queue in local.queue_names : name => queue if length(local.problems) == 0 }

  name = each.value
}

data "aws_sns_topic" "topics" {
  for_each = length(local.problems) == 0 ? local.topic_names : toset([])

  name = each.value
}
