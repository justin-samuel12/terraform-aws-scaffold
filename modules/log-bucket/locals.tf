locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  account_id = data.aws_caller_identity.current.account_id
  bucket_arn = "arn:aws:s3:::${var.name}"

  deny_insecure = {
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:*"
    Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
    Condition = { Bool = { "aws:SecureTransport" = "false" } }
  }

  load_balancer_paths = ["${local.bucket_arn}/AWSLogs/${local.account_id}/*", "${local.bucket_arn}/*/AWSLogs/${local.account_id}/*"]

  load_balancer = [
    {
      Sid       = "LoadBalancerDelivery"
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.current.arn }
      Action    = "s3:PutObject"
      Resource  = local.load_balancer_paths
    },
    {
      Sid       = "LoadBalancerLogDelivery"
      Effect    = "Allow"
      Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = local.load_balancer_paths
    },
  ]

  waf = [
    {
      Sid       = "WafLogDelivery"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${local.bucket_arn}/AWSLogs/${local.account_id}/*"
      Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceAccount" = local.account_id } }
    },
    {
      Sid       = "WafLogDeliveryAclCheck"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = "s3:GetBucketAcl"
      Resource  = local.bucket_arn
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    },
  ]

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat([local.deny_insecure], { waf = local.waf, load-balancer = local.load_balancer }[var.delivers])
  })
}
