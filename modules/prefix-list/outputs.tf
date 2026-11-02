output "ids" {
  description = "Prefix list name -> id."
  value       = { for name, list in aws_ec2_managed_prefix_list.lists : name => list.id }
}

output "arns" {
  description = "Prefix list name -> ARN, for sharing them with other accounts."
  value       = { for name, list in aws_ec2_managed_prefix_list.lists : name => list.arn }
}
