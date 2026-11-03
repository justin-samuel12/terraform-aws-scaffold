locals {
  suffix     = var.fifo ? ".fifo" : ""
  account_id = data.aws_caller_identity.current.account_id

  # Anything not over TLS is refused; within this account IAM alone decides, so the policy only adds services and other accounts.
  statements = concat(
    [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.topic.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }],
    length(var.publisher_services) == 0 ? [] : [{
      Sid       = "ServicesPublishForThisAccount"
      Effect    = "Allow"
      Principal = { Service = [for s in sort(tolist(var.publisher_services)) : "${s}.amazonaws.com"] }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.topic.arn
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }],
    length(var.publisher_accounts) == 0 ? [] : [{
      Sid       = "OtherAccountsPublish"
      Effect    = "Allow"
      Principal = { AWS = [for a in sort(tolist(var.publisher_accounts)) : "arn:${data.aws_partition.current.partition}:iam::${a}:root"] }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.topic.arn
    }],
  )
}
