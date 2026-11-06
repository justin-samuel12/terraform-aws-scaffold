data "aws_caller_identity" "current" {}

data "aws_kms_key" "data" {
  count = length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}
