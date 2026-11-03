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

# The region's hub account, for what AWS lets only the hub's owner do: accept and route an attachment, authorize a private zone,
# write records in the hub's zones. In single-account mode this is the same account as the provider above.
# tflint-ignore: terraform_unused_declarations # every stack has it; only the stacks whose template takes aws.hub use it
provider "aws" {
  alias               = "hub"
  region              = local.region
  profile             = local.cross_account ? local.hub_profile : local.profile
  allowed_account_ids = local.hub_pinned ? [local.hub_account] : null

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
      error_message = "No 12-digit account_id for ${local.environment}: read \"${local.account_id}\" from ${local.account_source}. Set it in ${local.region_file}, or once in config/global.yml for every environment (quoted, or YAML drops a leading zero). The account must exist before anything runs here."
    }
  }
}

check "team_set" {
  assert {
    condition     = local.team != null
    error_message = "No team for ${local.environment} in ${local.settings_file}: resources are created without a Team tag."
  }
}

# us-east-1, for what AWS keeps only there whatever the region: CloudFront's certificates and web ACLs.
# tflint-ignore: terraform_unused_declarations # every stack has it; only the stacks whose template takes aws.us_east_1 use it
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
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
