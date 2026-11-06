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
