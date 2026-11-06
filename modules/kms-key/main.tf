resource "aws_kms_key" "keys" {
  for_each = var.purposes

  description             = "${var.environment} ${each.key}"
  multi_region            = length(var.replica_regions) > 0
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 30
  policy                  = local.policies[each.key]

  tags = { Name = "${local.name_prefix}${each.key}", Purpose = each.key }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "keys" {
  for_each = var.purposes

  name          = "alias/${var.environment}-${each.key}"
  target_key_id = aws_kms_key.keys[each.key].key_id
}

resource "aws_kms_replica_key" "replicas" {
  for_each = { for pair in setproduct(keys(var.purposes), var.replica_regions) : "${pair[0]}/${pair[1]}" => { purpose = pair[0], region = pair[1] } }

  region                  = each.value.region
  description             = "${var.environment} ${each.value.purpose} (replica)"
  primary_key_arn         = aws_kms_key.keys[each.value.purpose].arn
  deletion_window_in_days = 30
  policy                  = local.policies[each.value.purpose]

  tags = { Name = "${local.name_prefix}${each.value.purpose}", Purpose = each.value.purpose }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "replicas" {
  for_each = aws_kms_replica_key.replicas

  region        = split("/", each.key)[1]
  name          = "alias/${var.environment}-${split("/", each.key)[0]}"
  target_key_id = each.value.key_id
}
