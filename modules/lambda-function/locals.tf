locals {
  statements = concat(
    [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.function.arn}:*" }],
    [for s in var.statements : { Effect = "Allow", Action = s.actions, Resource = s.resources }],
    [for q in(var.queue == null ? [] : [var.queue]) : { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"], Resource = q.arn }],
    [for q in(var.queue == null ? [] : [var.queue]) : { Effect = "Allow", Action = "kms:Decrypt", Resource = "*", Condition = { StringLike = { "kms:ViaService" = "sqs.*.amazonaws.com" } } }],
  )
}
