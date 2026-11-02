terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.63"

      # aws.hub: the account that owns the hosted zones (the region's hub account).
      configuration_aliases = [aws.hub]
    }
  }
}
