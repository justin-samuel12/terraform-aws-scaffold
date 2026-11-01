# The stack's own job: identity from its path, its endpoints.yml passed to templates/endpoints -- docs/endpoints.md.
mock_provider "aws" {}

override_data {
  target = module.endpoints.data.aws_vpc.vpc
  values = { id = "vpc-development", cidr_block = "10.41.0.0/16" }
}

override_data {
  target = module.endpoints.data.aws_subnets.tier
  values = { ids = ["subnet-private-1", "subnet-private-2", "subnet-private-3"] }
}

override_data {
  target = module.endpoints.module.vpc_endpoint.data.aws_region.current
  values = { region = "us-east-1" }
}

variables {
  config_dir  = "../../../../tests/stacks"
  config_file = "/nonexistent"
}

run "development" {
  command = plan

  assert {
    condition     = local.environment == "development" && local.region == "us-east-1" && local.component == "endpoints"
    error_message = "The stack reads its identity from its path."
  }

  assert {
    condition     = toset(keys(output.endpoints.ids)) == toset(["ssm", "ssmmessages", "ec2messages", "secretsmanager", "s3"])
    error_message = "Operations gets Session Manager's three endpoints, Secrets Manager and the S3 gateway."
  }
}
