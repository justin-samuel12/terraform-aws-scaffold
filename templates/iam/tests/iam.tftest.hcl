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
    condition     = length(local.problems) == 0 && jsondecode(local.module_roles.grafana.assume_role_policy) == { Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["sts:AssumeRole"], Principal = { Service = ["ec2.amazonaws.com"] } }] }
    error_message = "A role's trust is its assume_role_policy, as written."
  }

  assert {
    condition     = local.module_roles.grafana.policies == ["read-tags", "session-manager"] && local.module_roles.grafana.policy_arns == ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
    error_message = "managed_policy_arns takes an ARN as it is, and our own policies by name."
  }

  assert {
    condition     = jsonencode(local.module_roles.grafana.statements) == jsonencode([{ effect = "Allow", actions = ["s3:GetObject"], resources = ["arn:aws:s3:::grafana-dashboards/*"], condition = [{ test = "Bool", variable = "aws:SecureTransport", values = ["true"] }] }])
    error_message = "A role's own statement keeps its effect and condition."
  }

  assert {
    condition     = toset(keys(output.policy_arns)) == toset(["read-tags", "session-manager"]) && toset(keys(output.instance_profiles)) == toset(["grafana"])
    error_message = "One policy per file in policy/, one instance profile per file in instance-profile/, and nothing else."
  }
}

run "refused" {
  command = plan

  variables {
    config_dir = "tests/bad"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "stray.yml: a file belongs in role/ (an aws_iam_role), policy/ (an aws_iam_policy) or instance-profile/ (an aws_iam_instance_profile)"),
      contains(local.problems, "role/old.yml: keys are description, assume_role_policy, managed_policy_arns, statement"),
      contains(local.problems, "role/old.yml: needs assume_role_policy, a statement list naming who may assume the role"),
      contains(local.problems, "role/old.yml: a statement takes effect, actions, resources, condition, as aws_iam_policy_document does"),
      contains(local.problems, "role/old.yml: managed_policy_arns CloudWatchAgentServerPolicy is not a policy in this stack (a file named policy/CloudWatchAgentServerPolicy.yml) or an ARN"),
      contains(local.problems, "instance-profile/nobody.yml: role nobody is not a role in this stack (a file named role/nobody.yml)"),
    ])
    error_message = "Shortcuts, keys that are not arguments, a short policy name and a profile for a missing role are each named."
  }

  expect_failures = [output.arns]
}
