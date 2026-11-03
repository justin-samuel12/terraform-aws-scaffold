locals {
  account_id = data.aws_caller_identity.current.account_id
  root       = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"

  # Administered through IAM in this account; used only through the named services, by this account and any caller_accounts;
  # service_principals are AWS services acting for this account themselves, such as SNS delivering to an encrypted queue.
  policies = {
    for purpose, services in var.purposes : purpose => jsonencode({
      Version = "2012-10-17"
      Statement = concat([
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
              "kms:CallerAccount" = concat([local.account_id], sort(tolist(setsubtract(lookup(var.caller_accounts, purpose, []), [local.account_id]))))
              "kms:ViaService"    = flatten([for s in sort(tolist(services)) : [for r in concat([data.aws_region.current.region], sort(tolist(var.replica_regions))) : "${s}.${r}.amazonaws.com"]])
            }
          }
        },
        ], length(lookup(var.service_principals, purpose, [])) == 0 ? [] : [{
          Sid       = "ServicePrincipalsForThisAccount"
          Effect    = "Allow"
          Principal = { Service = [for s in sort(tolist(var.service_principals[purpose])) : "${s}.amazonaws.com"] }
          Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
          Resource  = "*"
          Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      }])
    })
  }
}
