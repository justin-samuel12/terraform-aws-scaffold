module "acm_certificate" {
  source = "../../modules/acm-certificate"

  providers = {
    aws     = aws
    aws.dns = aws.hub
  }

  certificates = {
    for name, c in local.certificates : name => {
      domain            = c.domain_name
      alternative_names = try(tolist(c.subject_alternative_names), [])
      zone              = c.zone
    }
  }
}
