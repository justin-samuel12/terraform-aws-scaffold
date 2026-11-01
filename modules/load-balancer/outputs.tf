output "dns_name" {
  description = "The load balancer's DNS name, for a Route 53 alias."
  value       = aws_lb.load_balancer.dns_name
}

output "target_group_arns" {
  description = "Target name -> target group ARN; compute registers its instances here."
  value       = { for name, group in aws_lb_target_group.targets : name => group.arn }
}
