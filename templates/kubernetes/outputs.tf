output "cluster" {
  description = "The cluster's name, ARN, API address, version, the security group EKS made for it, and the command that points kubectl at it; null with no cluster file."
  value = local.build ? {
    name                      = module.eks_cluster[0].name
    arn                       = module.eks_cluster[0].arn
    endpoint                  = module.eks_cluster[0].endpoint
    version                   = module.eks_cluster[0].version
    cluster_security_group_id = module.eks_cluster[0].cluster_security_group_id
    node_role_arn             = module.eks_cluster[0].node_role_arn
    kubeconfig                = "aws eks update-kubeconfig --region ${var.region} --name ${var.environment}"
  } : null

  precondition {
    condition     = local.usable
    error_message = "The cluster's files are not usable: ${join("; ", local.problems)}."
  }
}

output "apps" {
  description = "App -> its IAM role's ARN (for Vault's AWS auth), and the namespace and service account its pods run as."
  value = {
    for name, i in local.identities : i.app => {
      role_arn        = module.eks_workload_identity[0].arns[name]
      namespace       = i.namespace
      service_account = i.service_account
    } if local.build
  }
}
