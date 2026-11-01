output "ids" {
  description = "Prefix list name -> id."
  value       = { for name, list in aws_ec2_managed_prefix_list.lists : name => list.id }
}
