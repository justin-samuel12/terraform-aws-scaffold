# Public zones hold records that exist nowhere else: never destroyed by a plan, never force-destroyed.
resource "aws_route53_zone" "public" {
  for_each = var.public

  name    = each.key
  comment = "Managed by Terraform"

  tags = { Name = each.key }

  lifecycle {
    prevent_destroy = true
  }
}

# The VPC list is ignored after creation: each network stack associates its own VPC, and this stack must never undo that.
resource "aws_route53_zone" "private" {
  for_each = var.private

  name    = each.key
  comment = "Managed by Terraform; VPCs associate themselves"

  vpc {
    vpc_id = each.value
  }

  tags = { Name = each.key }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [vpc]
  }
}
