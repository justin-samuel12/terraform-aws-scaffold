output "ids" {
  description = "Group name -> security group id."
  value       = { for name, g in aws_security_group.groups : name => g.id }
}
