data "aws_default_tags" "current" {}

data "aws_route53_zone" "zones" {
  provider = aws.dns
  for_each = toset([for c in var.certificates : c.validation_zone])

  name         = each.key
  private_zone = false
}
