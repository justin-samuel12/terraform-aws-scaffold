locals {
  purposes = {
    data     = ["rds", "elasticfilesystem", "secretsmanager", "ec2", "backup", "s3", "eks"]
    backup   = ["backup"]
    messages = ["sqs", "sns"]
  }

  service_principals = { messages = ["sns", "events", "cloudwatch", "s3"], data = ["rds"] }
  caller_accounts    = { messages = [for env, account in module.ip_plan.accounts.environments : account if account != ""] }

  replica_regions = toset([for key in keys(module.ip_plan.networks) : split("/", key)[1] if split("/", key)[1] != var.region])
}
