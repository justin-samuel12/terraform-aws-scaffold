resource "aws_route53_zone" "public" {
  for_each = var.public

  name    = each.key
  comment = "Managed by Terraform"

  tags = { Name = "${local.name_prefix}${each.key}" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_zone" "private" {
  for_each = var.private

  name    = each.key
  comment = "Managed by Terraform; VPCs associate themselves"

  vpc {
    vpc_id = each.value
  }

  tags = { Name = "${local.name_prefix}${each.key}" }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [vpc]
  }
}
