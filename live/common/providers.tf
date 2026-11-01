provider "aws" {
  region              = local.region
  profile             = local.profile
  allowed_account_ids = local.pinned ? [local.account_id] : null

  default_tags {
    tags = merge(
      {
        ManagedBy   = "terraform"
        Environment = local.environment
        Component   = local.component
        Repository  = local.repository
      },
      local.team == null ? {} : { Team = local.team },
    )
  }
}

# tflint-ignore: terraform_unused_declarations # used by its precondition, which refuses a plan without an account
data "aws_caller_identity" "current" {
  lifecycle {
    precondition {
      condition     = local.pinned
      error_message = "No 12-digit account_id for ${local.environment} in ${local.region_file} (quote it, or YAML drops a leading zero). The account must exist before anything runs here."
    }
  }
}

check "team_set" {
  assert {
    condition     = local.team != null
    error_message = "No team for ${local.environment} in ${local.region_file}: resources are created without a Team tag."
  }
}
