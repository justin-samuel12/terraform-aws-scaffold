mock_provider "aws" {}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-1" }
}

variables {
  name                   = "development"
  kubernetes_version     = "1.34"
  subnet_ids             = ["subnet-1", "subnet-2", "subnet-3"]
  kms_key_arn            = "arn:aws:kms:us-east-1:111111111111:key/mrk-data"
  deletion_protection    = true
  endpoint_public_access = false
  access_entries = [
    {
      principal_arn              = "arn:aws:iam::111111111111:role/platform-admin"
      access_policy_associations = [{ policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy", access_scope = { type = "cluster" } }]
    },
    {
      principal_arn              = "arn:aws:iam::111111111111:role/developer"
      access_policy_associations = [{ policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy", access_scope = { type = "namespace", namespaces = ["orders-api"] } }]
    },
  ]
}

run "auto_mode" {
  command = plan

  assert {
    condition     = aws_eks_cluster.cluster.compute_config[0].enabled && toset(aws_eks_cluster.cluster.compute_config[0].node_pools) == toset(["general-purpose", "system"])
    error_message = "Auto Mode runs the nodes, with both built-in node pools."
  }

  assert {
    condition     = aws_eks_cluster.cluster.kubernetes_network_config[0].elastic_load_balancing[0].enabled && aws_eks_cluster.cluster.storage_config[0].block_storage[0].enabled && !aws_eks_cluster.cluster.bootstrap_self_managed_addons
    error_message = "Auto Mode also runs load balancing and block storage, with no self-managed add-ons."
  }

  assert {
    condition     = aws_iam_role.cluster.name == "development-eks-cluster-us-east-1" && aws_iam_role.node.name == "development-eks-node-us-east-1"
    error_message = "Roles are global, so their names carry the region."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role.cluster.assume_role_policy).Statement[0].Action) == toset(["sts:AssumeRole", "sts:TagSession"]) && jsondecode(aws_iam_role.cluster.assume_role_policy).Statement[0].Principal.Service == "eks.amazonaws.com"
    error_message = "Only EKS assumes the cluster role, and may tag its sessions."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.cluster) == 5 && contains(keys(aws_iam_role_policy_attachment.node), "AmazonEKSWorkerNodeMinimalPolicy") && contains(keys(aws_iam_role_policy_attachment.node), "AmazonEC2ContainerRegistryPullOnly")
    error_message = "The cluster role has the five Auto Mode policies; the node role the two minimal ones."
  }

  assert {
    condition     = aws_eks_cluster.cluster.access_config[0].authentication_mode == "API" && !aws_eks_cluster.cluster.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "Access is by access entries only; whoever creates the cluster gets nothing for it."
  }

  assert {
    condition     = length(aws_eks_access_entry.people) == 2 && aws_eks_access_policy_association.people["arn:aws:iam::111111111111:role/platform-admin arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"].access_scope[0].type == "cluster" && toset(aws_eks_access_policy_association.people["arn:aws:iam::111111111111:role/developer arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"].access_scope[0].namespaces) == toset(["orders-api"])
    error_message = "Each entry gets the policies it lists, at the scope it lists."
  }

  assert {
    condition     = aws_eks_cluster.cluster.vpc_config[0].endpoint_private_access && !aws_eks_cluster.cluster.vpc_config[0].endpoint_public_access
    error_message = "With endpoint_public_access false, the API is private."
  }

  assert {
    condition     = aws_eks_cluster.cluster.encryption_config[0].provider[0].key_arn == "arn:aws:kms:us-east-1:111111111111:key/mrk-data" && aws_eks_cluster.cluster.encryption_config[0].resources == toset(["secrets"])
    error_message = "Secrets are encrypted with the data key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.cluster.name == "/aws/eks/development/cluster" && aws_cloudwatch_log_group.cluster.retention_in_days == 365 && toset(aws_eks_cluster.cluster.enabled_cluster_log_types) == toset(["api", "audit", "authenticator"])
    error_message = "API, audit and authenticator logs, kept a year."
  }

  assert {
    condition     = aws_eks_cluster.cluster.deletion_protection && aws_eks_cluster.cluster.upgrade_policy[0].support_type == "STANDARD"
    error_message = "Protected from deletion, on standard support."
  }
}

run "public_endpoint" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["203.0.113.10/32"]
  }

  assert {
    condition     = aws_eks_cluster.cluster.vpc_config[0].endpoint_public_access && aws_eks_cluster.cluster.vpc_config[0].public_access_cidrs == toset(["203.0.113.10/32"])
    error_message = "Listed addresses, and only those, reach the API from the internet."
  }
}

run "rejects_open_endpoint" {
  command = plan

  variables {
    endpoint_public_access = true
    public_access_cidrs    = ["0.0.0.0/0"]
  }

  expect_failures = [var.public_access_cidrs]
}

run "rejects_bad_version" {
  command = plan

  variables {
    kubernetes_version = "latest"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_public_without_cidrs" {
  command = plan

  variables {
    endpoint_public_access = true
  }

  expect_failures = [var.public_access_cidrs]
}

run "rejects_a_namespace_scope_without_namespaces" {
  command = plan

  variables {
    access_entries = [{
      principal_arn              = "arn:aws:iam::111111111111:role/developer"
      access_policy_associations = [{ policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy", access_scope = { type = "namespace" } }]
    }]
  }

  expect_failures = [var.access_entries]
}

run "rejects_user_arn" {
  command = plan

  variables {
    access_entries = [{
      principal_arn              = "arn:aws:iam::111111111111:user/someone"
      access_policy_associations = [{ policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy", access_scope = { type = "cluster" } }]
    }]
  }

  expect_failures = [var.access_entries]
}
