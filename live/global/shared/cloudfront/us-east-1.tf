# CloudFront's certificates and WAF exist only in us-east-1, whatever the primary region -- docs/global.md.
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
