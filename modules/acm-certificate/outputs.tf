output "arns" {
  description = "Certificate name -> ARN, once validated."
  value       = { for name, validation in aws_acm_certificate_validation.certificates : name => validation.certificate_arn }
}
