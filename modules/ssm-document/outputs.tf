output "arns" {
  description = "Document name -> ARN; access is granted with ssm:StartSession or ssm:SendCommand on these."
  value       = { for name, d in aws_ssm_document.documents : name => d.arn }
}
