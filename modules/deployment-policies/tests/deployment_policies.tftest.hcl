variables {
  environment        = "staging"
  account_id         = "222222222222"
  hub_account_id     = "111111111111"
  state_bucket       = "example-terraform-state"
  github_repository  = "example-org/infrastructure"
  branch             = "main"
  other_environments = ["operations", "production", "shared"]
  hub_segments       = { "us-west-2" = { segment = "standard", propagates_to = ["standard", "shared"] } }
  duties             = { for name, d in yamldecode(file("../../templates/duties.yml")) : name => d if contains(["spokes", "any"], d.environments) && name != "pipeline" }
}

run "staging" {
  command = plan

  assert {
    condition     = toset(keys(var.duties)) == toset(["iam", "network", "services", "workload"])
    error_message = "A spoke deploys network, workload, services and iam, each with a role of its own; hub is the shared environment's, and pipeline is a person's."
  }

  assert {
    condition     = alltrue([for name, json in output.policies : length(json) <= 6144])
    error_message = "Every policy fits a customer managed policy, 6144 characters: ${jsonencode({ for name, json in output.policies : name => length(json) if length(json) > 6144 })}."
  }

  assert {
    condition     = alltrue([for name, d in var.duties : output.boundary_arns[name] == "arn:aws:iam::222222222222:policy/terraform-boundary-staging-${name}"])
    error_message = "Each duty's roles carry a boundary of their own."
  }

  assert {
    condition     = jsondecode(output.trust.apply).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:example-org/infrastructure:environment:staging:job_workflow_ref:example-org/infrastructure/.github/workflows/apply.yml@refs/heads/main"]
    error_message = "Only a job running in the staging GitHub environment, after its reviewers approve, may assume the staging apply roles."
  }

  assert {
    condition     = jsondecode(output.trust.propose).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:example-org/infrastructure:ref:refs/heads/main:job_workflow_ref:example-org/infrastructure/.github/workflows/apply.yml@refs/heads/main"]
    error_message = "Only the protected branch proposes plans."
  }

  assert {
    condition     = toset(jsondecode(output.trust.plan).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset(["repo:example-org/infrastructure:environment:plan:job_workflow_ref:example-org/infrastructure/.github/workflows/plan.yml@refs/heads/main", "repo:example-org/infrastructure:environment:plan:job_workflow_ref:example-org/infrastructure/.github/workflows/drift.yml@refs/heads/main"])
    error_message = "Only the trusted plan and drift workflows, from the protected branch, in the plan environment: never a pull request's own workflow."
  }

  assert {
    condition     = alltrue([for t in values(output.trust) : jsondecode(t).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"])
    error_message = "Every pipeline role requires a token meant for AWS STS."
  }

  assert {
    condition     = jsondecode(output.network_trust).Statement[0].Condition.ArnEquals["aws:PrincipalArn"] == "arn:aws:iam::222222222222:role/terraform-apply-staging-network"
    error_message = "Only staging's network apply role may assume terraform-network-staging in the hub."
  }
}

run "what_staging_roles_may_not_do" {
  command = plan

  module {
    source = "./tests/evaluate"
  }

  variables {
    documents = run.staging.documents
    requests  = yamldecode(file("tests/requests.yml")).refused
  }

  assert {
    condition     = alltrue([for name, allowed in output.allowed : !allowed])
    error_message = "Every one of these is refused: ${jsonencode({ for name, d in output.decisions : name => output.matched[name] if d == "allow" })}."
  }

  assert {
    condition     = !contains(values(output.decisions), "unsupported")
    error_message = "Every condition operator in these policies is one the evaluation models."
  }
}

run "what_staging_roles_may_do" {
  command = plan

  module {
    source = "./tests/evaluate"
  }

  variables {
    documents = run.staging.documents
    requests  = yamldecode(file("tests/requests.yml")).allowed
  }

  assert {
    condition     = alltrue(values(output.allowed))
    error_message = "Each of these is what a stack needs, so the limits leave it allowed: ${jsonencode({ for name, d in output.decisions : name => "${d} ${jsonencode(output.matched[name])}" if d != "allow" })}."
  }
}

run "shared" {
  command = plan

  variables {
    environment        = "shared"
    account_id         = "111111111111"
    hub_segments       = {}
    other_environments = ["operations", "production", "staging"]
    duties             = { for name, d in yamldecode(file("../../templates/duties.yml")) : name => d if contains(["shared", "any"], d.environments) && name != "pipeline" }
  }

  assert {
    condition     = alltrue([for name, json in output.policies : length(json) <= 6144])
    error_message = "Every policy of the hub's account fits a customer managed policy."
  }
}

run "what_the_hubs_roles_may_not_do" {
  command = plan

  module {
    source = "./tests/evaluate"
  }

  variables {
    documents = run.shared.documents
    requests  = yamldecode(file("tests/requests-shared.yml")).refused
  }

  assert {
    condition     = alltrue([for name, allowed in output.allowed : !allowed])
    error_message = "Every one of these is refused: ${jsonencode({ for name, d in output.decisions : name => output.matched[name] if d == "allow" })}."
  }
}

run "what_the_hubs_roles_may_do" {
  command = plan

  module {
    source = "./tests/evaluate"
  }

  variables {
    documents = run.shared.documents
    requests  = yamldecode(file("tests/requests-shared.yml")).allowed
  }

  assert {
    condition     = alltrue(values(output.allowed))
    error_message = "Each of these is what a hub stack needs: ${jsonencode({ for name, d in output.decisions : name => "${d} ${jsonencode(output.matched[name])}" if d != "allow" })}."
  }
}
