terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.63"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
