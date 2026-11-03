locals {
  suffix = var.fifo ? ".fifo" : ""

  # Anything not over TLS is refused, for everyone, before any allow is read.
  deny_insecure_transport = [for arn in [aws_sqs_queue.queue.arn, aws_sqs_queue.dead_letter.arn] : {
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "sqs:*"
    Resource  = arn
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }]

  # Within this account, IAM alone decides; the policy only adds topics and other accounts.
  queue_statements = concat(
    [local.deny_insecure_transport[0]],
    length(var.topic_arns) == 0 ? [] : [{
      Sid       = "TopicsDeliver"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.queue.arn
      Condition = { ArnEquals = { "aws:SourceArn" = sort(tolist(var.topic_arns)) } }
    }],
    length(var.sender_accounts) == 0 ? [] : [{
      Sid       = "OtherAccountsSend"
      Effect    = "Allow"
      Principal = { AWS = [for a in sort(tolist(var.sender_accounts)) : "arn:${data.aws_partition.current.partition}:iam::${a}:root"] }
      Action    = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
      Resource  = aws_sqs_queue.queue.arn
    }],
    length(var.consumer_accounts) == 0 ? [] : [{
      Sid       = "OtherAccountsConsume"
      Effect    = "Allow"
      Principal = { AWS = [for a in sort(tolist(var.consumer_accounts)) : "arn:${data.aws_partition.current.partition}:iam::${a}:root"] }
      Action    = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
      Resource  = aws_sqs_queue.queue.arn
    }],
  )
}
