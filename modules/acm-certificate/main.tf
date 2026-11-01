data "aws_route53_zone" "zones" {
  for_each = toset([for c in var.certificates : c.zone])

  name         = each.key
  private_zone = false
}

# Validated through DNS, so renewal is automatic for as long as the records stay.
resource "aws_acm_certificate" "certificates" {
  for_each = var.certificates

  domain_name               = each.value.domain
  subject_alternative_names = each.value.alternative_names
  validation_method         = "DNS"
  key_algorithm             = "RSA_2048"

  tags = { Name = each.key }

  lifecycle {
    create_before_destroy = true
  }
}

# Keyed by the names in config, which are known before the certificate exists; AWS fills in each record's value.
resource "aws_route53_record" "validation" {
  for_each = merge([
    for name, certificate in var.certificates : {
      for domain in concat([certificate.domain], certificate.alternative_names) : "${name}/${domain}" => { name = name, domain = domain, zone = certificate.zone }
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
