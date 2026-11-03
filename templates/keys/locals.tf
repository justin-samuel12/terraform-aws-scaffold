locals {
  # data: everything holding live data, and AWS Backup reading it. backup: the backup vault only, so a backup cannot be read with the live key and vice versa.
  # messages: queues and topics, apart from data so services publishing as themselves never reach the data key.
  purposes = {
    data     = ["rds", "elasticfilesystem", "secretsmanager", "ec2", "backup", "s3", "eks"]
    backup   = ["backup"]
    messages = ["sqs", "sns"]
  }

  # data: RDS itself reads a self-managed Active Directory secret encrypted with it, to join SQL Server to the domain.
  # messages: SNS delivers into encrypted queues; EventBridge, CloudWatch alarms and S3 events publish to encrypted topics, as themselves.
  # Every other environment's account may send through SQS and SNS too; each queue's and topic's own policy says who actually may.
  service_principals = { messages = ["sns", "events", "cloudwatch", "s3"], data = ["rds"] }
  caller_accounts    = { messages = [for env, account in module.ip_plan.accounts.environments : account if account != ""] }

  replica_regions = toset([for key in keys(module.ip_plan.networks) : split("/", key)[1] if split("/", key)[1] != var.region])
}
