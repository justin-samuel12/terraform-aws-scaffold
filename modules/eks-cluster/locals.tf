locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  cluster_policies = ["AmazonEKSClusterPolicy", "AmazonEKSComputePolicy", "AmazonEKSBlockStoragePolicy", "AmazonEKSLoadBalancingPolicy", "AmazonEKSNetworkingPolicy"]
  node_policies    = ["AmazonEKSWorkerNodeMinimalPolicy", "AmazonEC2ContainerRegistryPullOnly"]
  log_types        = ["api", "audit", "authenticator"]

  entries = { for e in var.access_entries : e.principal_arn => e }
  associations = merge([for e in var.access_entries : {
    for a in e.access_policy_associations : "${e.principal_arn} ${a.policy_arn}" => merge(a, { principal_arn = e.principal_arn })
  }]...)
}
