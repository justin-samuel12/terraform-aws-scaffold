# The providers every check uses, at the versions the stacks pin. bin/check-units and bin/check-files copy this folder's lock
# file into each folder they check, so init links providers from the cache and never downloads or rewrites them -- several
# checks then run side by side safely. Raise these with the stacks' own lock files (terraform init -upgrade in a stack).
terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.71.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.8.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.4.2"
    }
  }
}
