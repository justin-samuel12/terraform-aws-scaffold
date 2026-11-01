locals {
  account_id = data.aws_caller_identity.current.account_id
  root       = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"

  # Administered through IAM in this account; used only by the named services, on this account's behalf.
  policies = {
    for purpose, services in var.purposes : purpose => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "AccountAdministersThroughIam"
          Effect    = "Allow"
          Principal = { AWS = local.root }
          Action    = "kms:*"
          Resource  = "*"
        },
        {
          Sid       = "ServicesUseOnThisAccountsBehalf"
          Effect    = "Allow"
          Principal = { AWS = "*" }
          Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"]
          Resource  = "*"
          Condition = {
            StringEquals = {
              "kms:CallerAccount" = local.account_id
              "kms:ViaService"    = flatten([for s in sort(tolist(services)) : [for r in concat([data.aws_region.current.region], sort(tolist(var.replica_regions))) : "${s}.${r}.amazonaws.com"]])
            }
          }
        },
      ]
    })
  }
}
