# The stack's own job: identity from its path, its load balancer files passed to templates/load-balancers -- docs/load-balancers.md.
mock_provider "aws" {
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"] }
  }
  mock_data "aws_acm_certificate" {
    defaults = { arn = "arn:aws:acm:us-east-1:222222222222:certificate/00000000-0000-0000-0000-000000000000" }
  }
  mock_data "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::lb-logs-222222222222-us-east-1", id = "lb-logs-222222222222-us-east-1" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:222222222222:loadbalancer/app/mock/0000000000000000" }
  }
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:222222222222:listener/app/mock/0000000000000000/0000000000000000" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:222222222222:targetgroup/mock/0000000000000000" }
  }
}

override_data {
  target = module.load_balancers.data.aws_vpc.vpc
  values = { id = "vpc-development" }
}

variables {
  config_dir  = "../../../../tests/stacks"
  config_file = "/nonexistent"
}

run "development" {
  command = plan

  assert {
    condition     = local.environment == "development" && local.region == "us-east-1" && local.component == "load-balancers"
    error_message = "The stack reads its identity from its path."
  }

  assert {
    condition     = toset(keys(output.load_balancers.load_balancers)) == toset([for f in fileset(".", "*.yml") : trimsuffix(f, ".yml")])
    error_message = "Every load balancer file beside the stack becomes one load balancer, named after the file."
  }
}
