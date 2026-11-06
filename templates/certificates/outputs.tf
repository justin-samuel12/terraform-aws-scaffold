output "arns" {
  description = "Certificate name -> ARN; load balancers find certificates by domain, so nothing reads this but people."
  value       = module.acm_certificate.arns

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The certificate files are not usable: ${join("; ", local.problems)}."
  }
}
