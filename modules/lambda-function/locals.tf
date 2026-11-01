locals {
  statements = concat(
    [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.function.arn}:*" }],
    [for s in var.statements : { Effect = "Allow", Action = s.actions, Resource = s.resources }],
  )
}
