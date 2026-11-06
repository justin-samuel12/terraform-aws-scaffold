mock_provider "aws" {
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-operations" }
}

override_data {
  target = data.aws_kms_key.data[0]
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
}

override_data {
  target = data.aws_security_group.groups["kubernetes-api"]
  values = { id = "sg-kubernetes-api" }
}

override_data {
  target = data.aws_subnet.subnets["private-az1"]
  values = { id = "subnet-private-1" }
}

override_data {
  target = data.aws_subnet.subnets["private-az2"]
  values = { id = "subnet-private-2" }
}

override_data {
  target = module.eks_cluster[0].data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.eks_cluster[0].data.aws_region.current
  values = { region = "us-east-2" }
}

variables {
  environment = "operations"
  region      = "us-east-2"
  config_path = "../../tests/stacks"
}

run "cluster" {
  command = plan

  variables {
    config_dir = "tests/cluster"
  }

  assert {
    condition     = length(local.problems) == 0
    error_message = "The files are usable."
  }

  assert {
    condition     = module.eks_cluster[0].name == "operations" && output.cluster.kubeconfig == "aws eks update-kubeconfig --region us-east-2 --name operations"
    error_message = "One cluster, named after the environment, and the command that points kubectl at it."
  }

  assert {
    condition     = jsonencode(local.principals) == jsonencode(["arn:aws:iam::111111111111:role/platform-admin", "arn:aws:iam::111111111111:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Developer_0123456789abcdef"]) && length(local.access_entries[1].access_policy_associations) == 2 && jsonencode(local.access_entries[1].access_policy_associations[1].access_scope.namespaces) == jsonencode(["reports"])
    error_message = "A principal_arn that is a role's name is a role in this account; an ARN is used as written; each entry keeps its policies and scopes."
  }

  assert {
    condition     = toset(keys(data.aws_subnet.subnets)) == toset(["private-az1", "private-az2"]) && data.aws_subnet.subnets["private-az1"].id == "subnet-private-1" && !local.public
    error_message = "Subnets are named, or given by ID, which passes through; the API is private as written."
  }

  assert {
    condition     = toset(keys(local.identities)) == toset(["operations-orders-api-us-east-2", "operations-reports-worker-us-east-2"])
    error_message = "One role per app, named <environment>-<app>-<region>."
  }

  assert {
    condition     = module.eks_workload_identity[0].associations["operations-orders-api-us-east-2"] == { namespace = "orders-api", service_account = "orders-api" } && module.eks_workload_identity[0].associations["operations-reports-worker-us-east-2"] == { namespace = "reports", service_account = "worker" }
    error_message = "Each app's pods run as the namespace and service account its file names."
  }

  assert {
    condition     = local.identities["operations-reports-worker-us-east-2"].statements[0].condition[0].values == ["111111111111"] && local.identities["operations-orders-api-us-east-2"].statements[0].effect == "Allow"
    error_message = "Statements are written as in IAM, Allow by default."
  }
}

run "refused" {
  command = plan

  variables {
    config_dir = "tests/refused"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "cluster/staging.yml: the cluster is named for its environment, so its file is cluster/operations.yml"),
      contains(local.problems, "cluster/operations.yml: keys are version, deletion_protection, vpc_config, access_entry: aws_eks_cluster's, and access_entry for aws_eks_access_entry"),
      contains(local.problems, "cluster/operations.yml: needs deletion_protection, true or false"),
      contains(local.problems, "cluster/operations.yml: vpc_config.subnet_ids private-az9 is not a subnet of operations's VPC in us-east-2: data-az1, data-az2, data-az3, ops-az1, ops-az2, ops-az3, private-az1, private-az2, private-az3, transit-az1, transit-az2, transit-az3"),
      contains(local.problems, "cluster/operations.yml: public_access_cidrs 0.0.0.0/0 is not a CIDR such as 203.0.113.10/32, or is the whole internet"),
      contains(local.problems, "cluster/operations.yml: each access_entry takes principal_arn, access_policy_association, and needs both"),
      contains(local.problems, "cluster/operations.yml: principal_arn not a role is neither an IAM role's name nor a role's ARN"),
      contains(local.problems, "cluster/operations.yml: arn:aws:iam::111111111111:role/platform-admin has more than one access_entry; give it one, with each policy under access_policy_association"),
      contains(local.problems, "cluster/operations.yml: policy_arn AmazonEKSClusterAdminPolicy for platform-admin is an EKS access policy's ARN, such as arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"),
      contains(local.problems, "cluster/operations.yml: access_scope for platform-admin is type cluster, or type namespace with namespaces"),
      contains(local.problems, "orders-api.yml: keys are namespace, service_account, statement, managed_policy_arns: namespace and service_account as aws_eks_pod_identity_association takes them, statement and managed_policy_arns for its role"),
      contains(local.problems, "orders-api.yml: no statement may allow every action on every resource"),
      contains(local.problems, "unnamed.yml: needs namespace and service_account, Kubernetes names: lowercase letters, digits and hyphens"),
      contains(local.problems, "billing.yml: each statement takes effect, actions, resources, condition, and needs actions and resources"),
      contains(local.problems, "billing.yml: each condition takes test, variable and values, as in IAM"),
      contains(local.problems, "billing.yml: managed_policy_arns AmazonS3ReadOnlyAccess is a policy's ARN, such as arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"),
      contains(local.problems, "billing.yml: an app never takes AdministratorAccess, PowerUserAccess, IAMFullAccess"),
      contains(local.problems, "orders-api/orders-api: more than one app runs as this namespace and service account; each app has its own"),
    ])
    error_message = "Unknown keys, a misnamed cluster, bad access entries, an open endpoint, too much permission, missing names and a shared service account are each named."
  }

  assert {
    condition     = length(module.eks_cluster) == 0
    error_message = "Nothing is built from unusable files."
  }

  expect_failures = [output.cluster]
}

run "no_version" {
  command = plan

  variables {
    config_dir = "tests/no-version"
  }

  assert {
    condition     = local.problems == ["cluster/operations.yml: needs version, the Kubernetes version, such as 1.34; aws eks describe-cluster-versions lists the ones EKS offers"]
    error_message = "The version is chosen, never guessed."
  }

  expect_failures = [output.cluster]
}

run "apps_without_cluster" {
  command = plan

  variables {
    config_dir = "tests/orphan"
  }

  assert {
    condition     = local.problems == ["orders-api.yml: an app needs its cluster, cluster/operations.yml"]
    error_message = "Apps need a cluster."
  }

  expect_failures = [output.cluster]
}

run "empty" {
  command = plan

  variables {
    config_dir = "tests/nothing-here"
  }

  assert {
    condition     = length(module.eks_cluster) == 0 && output.cluster == null && length(local.problems) == 0
    error_message = "With no files, it builds nothing."
  }
}
