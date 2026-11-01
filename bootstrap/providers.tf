provider "aws" {
  region              = var.region
  profile             = var.profile
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = "shared"
      Component   = "bootstrap"
    }
  }
}

provider "aws" {
  alias               = "replica"
  region              = coalesce(var.replica_region, var.region)
  profile             = var.profile
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = "shared"
      Component   = "bootstrap"
    }
  }
}
