# Role files turned into roles, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

override_data {
  target = module.iam_role.data.aws_partition.current
  values = { partition = "aws" }
}

run "grafana" {
  command = plan

  variables {
    config_dir = "tests/roles"
  }

  assert {
    condition     = local.roles.grafana.services == toset(["ec2"]) && length(local.roles.grafana.managed_policies) == 2 && local.roles.grafana.policies == tolist(["read-tags", "session-manager"])
    error_message = "One role per file, with its trust, AWS managed policies and our own policies by name."
  }

  assert {
    condition     = toset(keys(output.policy_arns)) == toset(["read-tags", "session-manager"])
    error_message = "One customer-managed policy per file in policies/."
  }

  assert {
    condition     = toset(keys(output.instance_profiles)) == toset(["grafana"])
    error_message = "An EC2 role gets an instance profile."
  }
}
