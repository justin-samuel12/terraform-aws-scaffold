data "aws_kms_key" "vaults" {
  for_each = local.key_names

  region = each.value.region
  key_id = "alias/${each.value.kms_key_arn}"
}
