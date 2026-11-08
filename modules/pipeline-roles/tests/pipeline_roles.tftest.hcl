mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com" }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com" }
  }
}

variables {
  environment          = "staging"
  account_id           = "222222222222"
  hub_account_id       = "111111111111"
  github_repository    = "example-org/infrastructure"
  branch               = "main"
  create_oidc_provider = true
  state_bucket         = "example-terraform-state"
  hub_segments         = { "us-west-2" = { segment = "standard", propagates_to = ["standard"] } }
  duties               = { for name, d in yamldecode(file("../../templates/duties.yml")) : name => d if contains(["spokes", "any"], d.environments) && name != "pipeline" }
}

run "one_apply_role_per_duty" {
  command = plan

  assert {
    condition     = toset(keys(aws_iam_role.apply)) == toset(["iam", "network", "services", "workload"]) && alltrue([for duty, r in aws_iam_role.apply : r.name == "terraform-apply-staging-${duty}"])
    error_message = "A spoke has one apply role per duty, so a workload change never runs with the network's permissions."
  }

  assert {
    condition     = aws_iam_role.plan.name == "terraform-plan-staging" && aws_iam_role.propose.name == "terraform-propose-staging"
    error_message = "Planning a pull request and proposing a plan for review are separate roles."
  }

  assert {
    condition     = toset([for k, a in aws_iam_role_policy_attachment.apply : k if startswith(k, "workload/")]) == toset(["workload/read", "workload/workload", "workload/workload-state", "workload/workload-limits", "workload/workload-environment", "workload/workload-ownership"])
    error_message = "The workload role has the shared read policy and its own four, and nothing else: no AWS managed administrator policy."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.apply) == 6 * length(var.duties) && aws_iam_policy.read.name == "terraform-staging-read"
    error_message = "No pipeline role has AdministratorAccess or ReadOnlyAccess, whose reach includes every state file and secret."
  }

  assert {
    condition     = toset(keys(aws_iam_policy.boundary)) == toset(keys(var.duties)) && aws_iam_policy.boundary["workload"].name == "terraform-boundary-staging-workload"
    error_message = "Each duty has its own permission boundary."
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1 && length(data.aws_iam_openid_connect_provider.github) == 0
    error_message = "The stack that owns the account's GitHub provider creates it."
  }

  assert {
    condition     = length(aws_iam_role.network) == 0
    error_message = "Only the hub's account holds terraform-network-<environment> roles."
  }
}

run "trust" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.apply["workload"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:example-org/infrastructure:environment:staging:job_workflow_ref:example-org/infrastructure/.github/workflows/apply.yml@refs/heads/main"]
    error_message = "Apply roles trust only jobs in the staging GitHub environment, which its reviewers approve; never a branch or a pull request."
  }

  assert {
    condition     = jsondecode(aws_iam_role.propose.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:example-org/infrastructure:ref:refs/heads/main:job_workflow_ref:example-org/infrastructure/.github/workflows/apply.yml@refs/heads/main"]
    error_message = "Plans are proposed only from the protected branch."
  }

  assert {
    condition     = jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The roles trust this account's GitHub provider."
  }
}

run "the_hub_holds_the_network_roles" {
  command = plan

  variables {
    environment    = "shared"
    account_id     = "111111111111"
    hub_account_id = "111111111111"
    hub_segments   = {}
    duties         = { for name, d in yamldecode(file("../../templates/duties.yml")) : name => d if contains(["shared", "any"], d.environments) && name != "pipeline" }
    spokes = {
      staging    = { account_id = "222222222222", hub_segments = { "us-west-2" = { segment = "standard", propagates_to = ["standard"] } } }
      production = { account_id = "333333333333", hub_segments = { "us-east-2" = { segment = "restricted", propagates_to = [] } } }
    }
  }

  assert {
    condition     = toset(keys(aws_iam_role.apply)) == toset(["hub", "iam", "services"])
    error_message = "The shared environment deploys the hub, its shared services and its IAM files, each with its own role."
  }

  assert {
    condition     = aws_iam_role.network["staging"].name == "terraform-network-staging" && jsondecode(aws_iam_role.network["staging"].assume_role_policy).Statement[0].Condition.ArnEquals["aws:PrincipalArn"] == "arn:aws:iam::222222222222:role/terraform-apply-staging-network"
    error_message = "Each spoke's network role in the hub trusts that spoke's network apply role and nothing else."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.network["production"].policy).Statement : s if s.Sid == "JoinItsOwnSegmentUsEast2"]).Condition.StringEquals["aws:ResourceTag/Segment"] == "restricted"
    error_message = "Production's network role may join only production's segment."
  }

  assert {
    condition     = length([for s in jsondecode(aws_iam_role_policy.network["production"].policy).Statement : s if startswith(s.Sid, "AnnounceToItsSegments")]) == 0
    error_message = "An environment that announces to no segment gets no propagation permission at all."
  }
}

run "another_stack_owns_the_provider" {
  command = plan

  variables {
    create_oidc_provider = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && output.oidc_provider_arn == "arn:aws:iam::222222222222:oidc-provider/token.actions.githubusercontent.com"
    error_message = "In an account shared with another environment, the provider is looked up, not created twice."
  }
}

run "rejects_a_repository_that_is_not_owner_and_name" {
  command = plan

  variables {
    github_repository = "infrastructure"
  }

  expect_failures = [var.github_repository]
}
