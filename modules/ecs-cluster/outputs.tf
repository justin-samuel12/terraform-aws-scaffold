output "arn" {
  description = "The cluster's ARN."
  value       = aws_ecs_cluster.cluster.arn
}

output "name" {
  description = "The cluster's name: the environment's."
  value       = aws_ecs_cluster.cluster.name

  depends_on = [aws_ecs_cluster_capacity_providers.cluster]
}

output "exec" {
  description = "Where ECS Exec sessions are logged and the key that encrypts them, for the permissions each task role needs to use it."
  value = {
    log_group_name = aws_cloudwatch_log_group.exec.name
    log_group_arn  = aws_cloudwatch_log_group.exec.arn
    kms_key_arn    = var.kms_key_arn
  }
}
