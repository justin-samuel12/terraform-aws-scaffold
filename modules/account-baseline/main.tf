resource "aws_s3_account_public_access_block" "account" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "regions" {
  for_each = var.regions

  region  = each.key
  enabled = true
}

resource "aws_ebs_snapshot_block_public_access" "regions" {
  for_each = var.regions

  region = each.key
  state  = "block-all-sharing"
}

resource "aws_accessanalyzer_analyzer" "regions" {
  for_each = var.regions

  region        = each.key
  analyzer_name = "account-${each.key}"
  type          = "ACCOUNT"
}
