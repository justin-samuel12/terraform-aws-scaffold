module "acm_certificate" {
  source = "../../modules/acm-certificate"

  certificates = {
    for name, c in local.certificates : name => {
      domain            = c.domain
      alternative_names = try(tolist(c.alternative_names), [])
      zone              = c.zone
    }
  }
}
