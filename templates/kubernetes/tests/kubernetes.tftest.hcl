# cluster.yml and one <app>.yml per app turned into an EKS Auto Mode cluster and app roles, against a mocked AWS -- docs/kubernetes.md.
mock_provider "aws" {
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-ops-1", "subnet-ops-2", "subnet-ops-3"] }
  }
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
  target = module.eks_cluster[0].data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.eks_cluster[0].data.aws_region.current
  values = { region = "us-east-2" }
}

override_data {
  target = module.eks_workload_identity[0].data.aws_partition.current
  values = { partition = "aws" }
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
    condition     = local.role_arns.admins == ["arn:aws:iam::111111111111:role/platform-admin"] && local.role_arns.viewers == ["arn:aws:iam::111111111111:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Developer_0123456789abcdef"]
    error_message = "A role's name is a role in this account; an ARN is used as written."
  }

  assert {
    condition     = toset(keys(local.identities)) == toset(["operations-orders-api-us-east-2", "operations-reports-worker-us-east-2"])
    error_message = "One role per app, named <environment>-<app>-<region>."
  }

  assert {
    condition     = module.eks_workload_identity[0].associations["operations-orders-api-us-east-2"] == { namespace = "orders-api", service_account = "orders-api" } && module.eks_workload_identity[0].associations["operations-reports-worker-us-east-2"] == { namespace = "reports", service_account = "worker" }
    error_message = "The namespace and service account are the app's name unless its file says otherwise."
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
      contains(local.problems, "cluster.yml: keys are version, admins, viewers, public_access_cidrs, security_groups, deletion_protection"),
      contains(local.problems, "cluster.yml: not a role in viewers is neither an IAM role's name nor a role's ARN"),
      contains(local.problems, "cluster.yml: arn:aws:iam::111111111111:role/platform-admin is in both admins and viewers"),
      contains(local.problems, "cluster.yml: public_access_cidrs 0.0.0.0/0 is not a CIDR such as 203.0.113.10/32, or is the whole internet"),
      contains(local.problems, "orders-api.yml: keys are namespace, service_account, statement, managed_policies"),
      contains(local.problems, "orders-api.yml: no statement may allow every action on every resource"),
      contains(local.problems, "billing.yml: each statement takes effect, actions, resources, condition, and needs actions and resources"),
      contains(local.problems, "billing.yml: each condition takes test, variable and values, as in IAM"),
      contains(local.problems, "billing.yml: an app never takes AdministratorAccess, PowerUserAccess or IAMFullAccess"),
      contains(local.problems, "orders-api/orders-api: more than one app runs as this namespace and service account; each app has its own"),
    ])
    error_message = "Unknown keys, bad people, an open endpoint, too much permission and a shared service account are each named."
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
    condition     = local.problems == ["cluster.yml: needs version, the Kubernetes version, such as 1.34; aws eks describe-cluster-versions lists the ones EKS offers"]
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
    condition     = local.problems == ["orders-api.yml: an app needs cluster.yml beside it, for the cluster it runs in"]
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
