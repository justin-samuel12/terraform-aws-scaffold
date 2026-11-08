module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"
  count  = local.build ? 1 : 0

  name                   = var.environment
  kubernetes_version     = tostring(local.cluster.version)
  deletion_protection    = tobool(local.cluster.deletion_protection)
  subnet_ids             = [for s in local.subnets : startswith(s, "subnet-") ? s : data.aws_subnet.subnets[s].id]
  security_group_ids     = [for g in local.security_groups : startswith(g, "sg-") ? g : data.aws_security_group.groups[g].id]
  endpoint_public_access = local.public
  public_access_cidrs    = local.public_cidrs
  kms_key_arn            = data.aws_kms_key.data[0].arn
  access_entries         = local.access_entries

  role_boundary = module.role_boundary.role_boundary
}

module "eks_workload_identity" {
  source = "../../modules/eks-workload-identity"
  count  = local.build && length(local.identities) > 0 ? 1 : 0

  cluster_name = module.eks_cluster[0].name
  cluster_arn  = module.eks_cluster[0].arn
  roles = {
    for name, i in local.identities : name => {
      description     = "${i.app}'s pods in ${var.environment}, ${var.region}"
      namespace       = i.namespace
      service_account = i.service_account
      policy_arns     = i.policy_arns
      statements      = i.statements
    }
  }

  role_boundary = module.role_boundary.role_boundary
}

module "role_boundary" {
  source = "../../modules/role-boundary"

  duties_file = "${path.module}/../duties.yml"
}
