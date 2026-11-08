resource "aws_acm_certificate" "certificates" {
  for_each = var.certificates

  domain_name               = each.value.domain_name
  subject_alternative_names = each.value.subject_alternative_names
  validation_method         = each.value.validation_method
  key_algorithm             = each.value.key_algorithm

  dynamic "options" {
    for_each = each.value.options == null ? [] : [each.value.options]

    content {
      export                                      = options.value.export
      certificate_transparency_logging_preference = options.value.certificate_transparency_logging_preference
    }
  }

  tags = merge(each.value.tags, { Name = "${local.name_prefix}${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  provider = aws.dns
  for_each = merge([
    for name, certificate in var.certificates : {
      for domain in concat([certificate.domain_name], certificate.subject_alternative_names) : "${name}/${domain}" => { name = name, domain = domain, zone = certificate.validation_zone }
    }
  ]...)

  zone_id         = data.aws_route53_zone.zones[each.value.zone].zone_id
  name            = one([for o in aws_acm_certificate.certificates[each.value.name].domain_validation_options : o.resource_record_name if o.domain_name == each.value.domain])
  type            = one([for o in aws_acm_certificate.certificates[each.value.name].domain_validation_options : o.resource_record_type if o.domain_name == each.value.domain])
  records         = [one([for o in aws_acm_certificate.certificates[each.value.name].domain_validation_options : o.resource_record_value if o.domain_name == each.value.domain])]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "certificates" {
  for_each = var.certificates

  certificate_arn         = aws_acm_certificate.certificates[each.key].arn
  validation_record_fqdns = [for key, record in aws_route53_record.validation : record.fqdn if startswith(key, "${each.key}/")]
}
