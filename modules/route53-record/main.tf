resource "aws_route53_record" "records" {
  for_each = var.records

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.alias == null ? each.value.records : null

  dynamic "alias" {
    for_each = each.value.alias == null ? [] : [each.value.alias]
    content {
      name                   = alias.value.name
      zone_id                = alias.value.zone_id
      evaluate_target_health = alias.value.evaluate_target_health
    }
  }
}
