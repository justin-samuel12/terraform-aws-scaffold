locals {
  # data: everything holding live data, and AWS Backup reading it. backup: the backup vault only, so a backup cannot be read with the live key and vice versa.
  purposes = {
    data   = ["rds", "elasticfilesystem", "secretsmanager", "ec2", "backup"]
    backup = ["backup"]
  }

  replica_regions = toset([for key in keys(module.ip_plan.networks) : split("/", key)[1] if split("/", key)[1] != var.region])
}
