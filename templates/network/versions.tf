terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.63"

      # aws.hub: the region's hub account, for what only the hub's owner may do.
      configuration_aliases = [aws.hub]
    }
  }
}
