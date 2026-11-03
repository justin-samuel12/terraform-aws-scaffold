module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Everything shared is found by name and tags: the VPC, its private subnets, security groups and the data key.
data "aws_vpc" "vpc" {
  count = local.build ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
    Name        = "vpc-01"
  }
}

data "aws_subnets" "private" {
  count = local.build ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc[0].id]
  }

  tags = { Tier = "private" }
}

data "aws_security_group" "groups" {
  for_each = local.build ? toset([for g in try(tolist(local.cluster.security_groups), []) : tostring(g)]) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Name = each.key }
}

data "aws_kms_key" "data" {
  count = local.build ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"
  count  = local.build ? 1 : 0

  name                = var.environment
  kubernetes_version  = tostring(local.cluster.version)
  subnet_ids          = data.aws_subnets.private[0].ids
  security_group_ids  = [for g in try(tolist(local.cluster.security_groups), []) : data.aws_security_group.groups[tostring(g)].id]
  kms_key_arn         = data.aws_kms_key.data[0].arn
  admins              = local.role_arns.admins
  viewers             = local.role_arns.viewers
  public_access_cidrs = [for c in try(tolist(local.cluster.public_access_cidrs), []) : tostring(c)]
  deletion_protection = try(tobool(local.cluster.deletion_protection), true)
}

module "eks_workload_identity" {
  source = "../../modules/eks-workload-identity"
  count  = local.build && length(local.identities) > 0 ? 1 : 0

  cluster_name = module.eks_cluster[0].name
  cluster_arn  = module.eks_cluster[0].arn
  roles = {
    for name, i in local.identities : name => {
      description      = "${i.app}'s pods in ${var.environment}, ${var.region}"
      namespace        = i.namespace
      service_account  = i.service_account
      managed_policies = i.managed_policies
      statements       = i.statements
    }
  }
}
