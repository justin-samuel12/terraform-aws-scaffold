resource "aws_iam_role" "cluster" {
  name                 = "${var.name}-eks-cluster-${data.aws_region.current.region}"
  description          = "EKS running the ${var.name} cluster's control plane and Auto Mode"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = { Name = "${local.name_prefix}EKS Cluster Role" }
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset(local.cluster_policies)

  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.key}"
}

resource "aws_iam_role_policy" "cluster_kms" {
  name = "${var.name}-eks-cluster-kms"
  role = aws_iam_role.cluster.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey", "kms:CreateGrant", "kms:ListGrants"]
      Resource = var.kms_key_arn
    }]
  })
}

resource "aws_iam_role" "node" {
  name                 = "${var.name}-eks-node-${data.aws_region.current.region}"
  description          = "The servers EKS Auto Mode runs for the ${var.name} cluster"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${local.name_prefix}EKS Node Role" }
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset(local.node_policies)

  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.key}"
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days

  tags = { Name = "${local.name_prefix}EKS Cluster" }
}

resource "aws_eks_cluster" "cluster" {
  name                          = var.name
  version                       = var.kubernetes_version
  role_arn                      = aws_iam_role.cluster.arn
  bootstrap_self_managed_addons = false
  deletion_protection           = var.deletion_protection
  enabled_cluster_log_types     = local.log_types

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.node.arn
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = var.security_group_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = var.kms_key_arn
    }
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = { Name = "${local.name_prefix}EKS Cluster" }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_iam_role_policy.cluster_kms,
    aws_iam_role_policy_attachment.node,
    aws_cloudwatch_log_group.cluster,
  ]
}

resource "aws_eks_access_entry" "people" {
  for_each = local.entries

  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = each.key
  type          = "STANDARD"

  tags = { Name = "${local.name_prefix}EKS Cluster" }
}

resource "aws_eks_access_policy_association" "people" {
  for_each = local.associations

  cluster_name  = aws_eks_cluster.cluster.name
  principal_arn = aws_eks_access_entry.people[each.value.principal_arn].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope.type
    namespaces = each.value.access_scope.type == "namespace" ? each.value.access_scope.namespaces : null
  }
}
