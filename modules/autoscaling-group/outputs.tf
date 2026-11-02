output "name" {
  description = "The Auto Scaling group's name, which CodeDeploy deploys to."
  value       = aws_autoscaling_group.group.name
}

output "launch_template_id" {
  description = "The launch template's ID."
  value       = aws_launch_template.group.id
}
