mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "222222222222" }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  duties_file = "../../templates/duties.yml"
}

run "a_workload_stacks_roles_carry_the_workload_boundary" {
  command = plan

  override_data {
    target = data.aws_default_tags.current
    values = { tags = { Environment = "staging", Component = "compute" } }
  }

  assert {
    condition     = output.role_boundary == { path = "/deployed/", permissions_boundary = "arn:aws:iam::222222222222:policy/terraform-boundary-staging-workload" }
    error_message = "A compute stack's roles go under /deployed/ with staging's workload boundary."
  }
}

run "a_network_stacks_roles_carry_the_network_boundary" {
  command = plan

  override_data {
    target = data.aws_default_tags.current
    values = { tags = { Environment = "production", Component = "network" } }
  }

  assert {
    condition     = output.role_boundary.permissions_boundary == "arn:aws:iam::222222222222:policy/terraform-boundary-production-network" && output.duty == "network"
    error_message = "A network stack's flow-log role carries the network boundary."
  }
}

run "a_component_without_a_duty_is_refused" {
  command = plan

  override_data {
    target = data.aws_default_tags.current
    values = { tags = { Environment = "staging", Component = "mystery" } }
  }

  expect_failures = [output.role_boundary]
}

run "no_tags_no_boundary" {
  command = plan

  override_data {
    target = data.aws_default_tags.current
    values = { tags = {} }
  }

  assert {
    condition     = output.role_boundary == null
    error_message = "A module's own tests, with no default tags, create roles as before."
  }
}
