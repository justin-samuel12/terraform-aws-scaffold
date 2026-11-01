# The stack's own job: identity from its path, its group files passed to templates/security-groups -- docs/security-groups.md.
mock_provider "aws" {}

override_data {
  target = module.security_groups.data.aws_vpc.vpc
  values = { id = "vpc-development" }
}

variables {
  config_dir  = "../../../../tests/stacks"
  config_file = "/nonexistent"
}

run "development" {
  command = plan

  assert {
    condition     = local.environment == "development" && local.region == "us-east-1" && local.component == "security-groups"
    error_message = "The stack reads its identity from its path."
  }

  assert {
    condition     = toset(keys(output.security_groups.ids)) == toset([for f in fileset(".", "*.yml") : trimsuffix(f, ".yml")])
    error_message = "Every group file beside the stack becomes one group, named after the file."
  }
}
