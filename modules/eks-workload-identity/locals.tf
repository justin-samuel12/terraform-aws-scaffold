locals {
  account_id = split(":", var.cluster_arn)[4]
}
