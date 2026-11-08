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
      },
      local.repository == null ? {} : { Repository = local.repository },
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
      role_arn     = "arn:aws:iam::${assume_role.value}:role/${local.dns_role}"
      session_name = "dns-${local.environment}"
    }
  }

  default_tags {
    tags = merge(
      {
        ManagedBy   = "terraform"
        Environment = local.environment
        Component   = local.component
      },
      local.repository == null ? {} : { Repository = local.repository },
      local.team == null ? {} : { Team = local.team },
    )
  }
}

# tflint-ignore: terraform_unused_declarations
provider "aws" {
  alias               = "hub"
  region              = local.region
  profile             = local.hub_profile
  allowed_account_ids = local.hub_pinned ? [local.hub_account] : null

  default_tags {
    tags = merge(
      {
        ManagedBy   = "terraform"
        Environment = local.environment
        Component   = local.component
      },
      local.repository == null ? {} : { Repository = local.repository },
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

    precondition {
      condition     = fileexists(local.region_file)
      error_message = "${local.location == "global" ? "No hub in config/ has primary: true, so global stacks have no region" : "${local.region} has no ${local.region_file}"}: a stack deploys only to a region the configuration names."
    }

    precondition {
      condition     = local.location == "global" || local.environment == "shared" || can(local.region_config.vpcs[local.environment])
      error_message = "${local.environment} is not an environment in ${local.region_file}: a stack deploys only where config/ puts its environment, so it never falls back to another account."
    }

    precondition {
      condition     = local.path_stack == local.declared_stack
      error_message = "stack.tf says this stack is ${local.declared_stack}, but it sits in live/${local.path_stack}. A copied or moved folder would otherwise deploy to the wrong place and share another stack's state. If the move is intended, run make backends and review the new stack.tf and backend.tf."
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
      },
      local.repository == null ? {} : { Repository = local.repository },
      local.team == null ? {} : { Team = local.team },
    )
  }
}
