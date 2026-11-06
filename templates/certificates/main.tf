module "acm_certificate" {
  source = "../../modules/acm-certificate"

  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  certificates = local.certificates
}
