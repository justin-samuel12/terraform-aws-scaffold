locals {
  cluster_policies = ["AmazonEKSClusterPolicy", "AmazonEKSComputePolicy", "AmazonEKSBlockStoragePolicy", "AmazonEKSLoadBalancingPolicy", "AmazonEKSNetworkingPolicy"]
  node_policies    = ["AmazonEKSWorkerNodeMinimalPolicy", "AmazonEC2ContainerRegistryPullOnly"]
  log_types        = ["api", "audit", "authenticator"]

  access = merge(
    { for arn in var.viewers : arn => "AmazonEKSViewPolicy" },
    { for arn in var.admins : arn => "AmazonEKSClusterAdminPolicy" },
  )
}
