output "name" {
  description = "The cluster's name."
  value       = aws_eks_cluster.cluster.name
}

output "arn" {
  description = "The cluster's ARN."
  value       = aws_eks_cluster.cluster.arn
}

output "endpoint" {
  description = "The Kubernetes API's address, private unless endpoint_public_access is true."
  value       = aws_eks_cluster.cluster.endpoint
}

output "version" {
  description = "The Kubernetes version the control plane runs."
  value       = aws_eks_cluster.cluster.version
}

output "cluster_security_group_id" {
  description = "The security group EKS made for the control plane and the nodes; allow traffic from it to reach what pods call, such as Vault or a database."
  value       = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  description = "The role every node runs as; pods get their own roles instead."
  value       = aws_iam_role.node.arn
}

output "log_group" {
  description = "The control plane's log group."
  value       = aws_cloudwatch_log_group.cluster.name
}
