mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
  }
}

variables {
  config_path = "tests/one-account"
}

run "one_account_shared_owns_the_provider" {
  command = plan

  variables {
    environment = "shared"
  }

  assert {
    condition     = output.creates_oidc_provider
    error_message = "With every environment in one account, the shared stack creates the account's one GitHub provider."
  }

  assert {
    condition     = tolist(output.duties) == tolist(["hub", "iam", "services"])
    error_message = "The shared environment deploys the hub, its shared services and its IAM files."
  }

  assert {
    condition     = toset(keys(module.pipeline_roles[0].network_role_arns)) == toset(["operations", "production", "staging"])
    error_message = "The hub holds one network role per environment attached to it."
  }
}

run "one_account_others_look_it_up" {
  command = plan

  variables {
    environment = "staging"
  }

  assert {
    condition     = !output.creates_oidc_provider
    error_message = "The other environments in that account look it up rather than create a second one."
  }

  assert {
    condition     = tolist(output.duties) == tolist(["iam", "network", "services", "workload"])
    error_message = "A spoke deploys its network, its workloads, its own services and its IAM files, each with its own role."
  }

  assert {
    condition     = one([for s in module.pipeline_roles[0].documents["network-role"] : s if s.Sid == "JoinItsOwnSegmentUsWest2"]).Condition.StringEquals["aws:ResourceTag/Segment"] == "standard"
    error_message = "Staging's hub role joins only staging's segment, standard, read from config/."
  }
}

run "own_accounts_each_create_their_provider" {
  command = plan

  variables {
    config_path = "tests/own-accounts"
    environment = "operations"
  }

  assert {
    condition     = output.creates_oidc_provider
    error_message = "An environment alone in its account creates that account's provider."
  }
}

run "production_must_have_its_own_account" {
  command = plan

  variables {
    config_path = "tests/shared-production"
    environment = "staging"
  }

  assert {
    condition     = length(module.pipeline_roles) == 0 && anytrue([for p in local.problems : startswith(p, "production shares account 333333333333 with staging.")])
    error_message = "Production sharing an account with staging is refused unless config/global.yml accepts it, since tags cannot keep every resource apart."
  }

  expect_failures = [output.plan_role_arn]
}

run "a_parents_gateway_gives_the_hub_role_nothing_to_route" {
  command = plan

  variables {
    config_path = "tests/parent"
    environment = "production"
  }

  assert {
    condition     = length([for s in module.pipeline_roles[0].documents["network-role"] : s if can(regex("Segment|Segments|Attachment", s.Sid))]) == 0
    error_message = "Where a parent runs the gateway, production's hub role can accept, join and announce nothing."
  }
}

run "an_environment_name_cannot_contain_another_as_its_prefix" {
  command = plan

  variables {
    config_path = "tests/collision"
    environment = "staging"
  }

  assert {
    condition     = length(module.pipeline_roles) == 0 && anytrue([for p in local.problems : strcontains(p, "staging-dr's name starts with staging-")])
    error_message = "staging's bucket prefix would cover staging-dr's buckets, so the pair is refused."
  }

  expect_failures = [output.plan_role_arn]
}

run "refuses_incomplete_settings" {
  command = plan

  variables {
    config_path = "tests/unset"
    environment = "staging"
  }

  assert {
    condition     = length(module.pipeline_roles) == 0
    error_message = "Nothing is built from incomplete settings."
  }

  assert {
    condition     = toset(local.problems) == toset(["config/global.yml: pipeline takes github_repository, branch, dedicated_accounts, approvals, reviewers; repo is not one of them", "config/global.yml: pipeline.github_repository is the GitHub repository, owner/name, whose workflows deploy", "config/global.yml: pipeline.branch is the protected branch that plans are proposed from", "config/global.yml: state.bucket is empty; make bootstrap creates the bucket and writes its name", "no 12-digit account_id for staging in config/: its roles live in its account", "no 12-digit account_id for the hub in config/: each network's hub role lives there"])
    error_message = "Each missing or unknown setting is named: ${jsonencode(local.problems)}."
  }

  expect_failures = [output.plan_role_arn]
}
