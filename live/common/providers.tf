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

# tflint-ignore: terraform_unused_declarations
provider "aws" {
  alias               = "dns"
  region              = local.region
  profile             = local.profile
  allowed_account_ids = local.hub_pinned ? [local.hub_account] : null

  dynamic "assume_role" {
    for_each = local.cross_account ? [local.hub_account] : []
    content {
      role_arn     = "arn:aws:iam::${assume_role.value}:role/dns-${local.environment}"
      session_name = "dns-${local.environment}"
    }
  }

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

# tflint-ignore: terraform_unused_declarations
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

# tflint-ignore: terraform_unused_declarations
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

# tflint-ignore: terraform_unused_declarations
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
