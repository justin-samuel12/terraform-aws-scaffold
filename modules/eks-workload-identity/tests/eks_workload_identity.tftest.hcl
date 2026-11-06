mock_provider "aws" {}

variables {
  cluster_name = "development"
  cluster_arn  = "arn:aws:eks:us-east-1:111111111111:cluster/development"
  roles = {
    development-orders-api-us-east-1 = {
      description     = "orders-api's pods in development, us-east-1"
      namespace       = "orders-api"
      service_account = "orders-api"
      policy_arns     = ["arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"]
      statements      = [{ actions = ["sqs:SendMessage"], resources = ["arn:aws:sqs:us-east-1:111111111111:development-orders"] }]
    }
  }
}

run "app_role" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.roles["development-orders-api-us-east-1"].assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com" && toset(jsondecode(aws_iam_role.roles["development-orders-api-us-east-1"].assume_role_policy).Statement[0].Action) == toset(["sts:AssumeRole", "sts:TagSession"])
    error_message = "Only EKS Pod Identity assumes an app's role."
  }

  assert {
    condition     = jsondecode(aws_iam_role.roles["development-orders-api-us-east-1"].assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:eks:us-east-1:111111111111:cluster/development" && jsondecode(aws_iam_role.roles["development-orders-api-us-east-1"].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111"
    error_message = "And only for this cluster, in this account."
  }

  assert {
    condition     = aws_eks_pod_identity_association.associations["development-orders-api-us-east-1"].namespace == "orders-api" && aws_eks_pod_identity_association.associations["development-orders-api-us-east-1"].service_account == "orders-api"
    error_message = "The role goes to pods running as the app's service account in its namespace."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.managed["development-orders-api-us-east-1 arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"].policy_arn == "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess" && length(aws_iam_role_policy.own) == 1
    error_message = "Policies by ARN, statements as the role's own policy."
  }
}

run "rejects_shared_service_account" {
  command = plan

  variables {
    roles = {
      development-a-us-east-1 = { description = "a", namespace = "shop", service_account = "app" }
      development-b-us-east-1 = { description = "b", namespace = "shop", service_account = "app" }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_everything_on_everything" {
  command = plan

  variables {
    roles = {
      development-a-us-east-1 = { description = "a", namespace = "a", service_account = "a", statements = [{ actions = ["*"], resources = ["*"] }] }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_administrator" {
  command = plan

  variables {
    roles = {
      development-a-us-east-1 = { description = "a", namespace = "a", service_account = "a", policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"] }
    }
  }

  expect_failures = [var.roles]
}
