output "arns" {
  description = "Certificate name -> ARN; load balancers find certificates by domain, so nothing reads this but people."
  value       = module.acm_certificate.arns
}
