# Plans a stack's own files against a mocked AWS that answers like the real one: make check-files.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "222222222222", arn = "arn:aws:iam::222222222222:root" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-00000000000000001", cidr_block = "10.41.0.0/16" }
  }
  mock_data "aws_acm_certificate" {
    defaults = { arn = "arn:aws:acm:us-east-1:222222222222:certificate/00000000-0000-0000-0000-000000000000" }
  }
  mock_data "aws_availability_zones" {
    defaults = { zone_ids = ["use1-az1", "use1-az2", "use1-az4"], names = ["us-east-1a", "us-east-1b", "us-east-1d"] }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"] }
  }
  mock_data "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:222222222222:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_data "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:222222222222:loadbalancer/app/mock/0000000000000000", dns_name = "mock-0000.us-east-1.elb.amazonaws.com", zone_id = "Z35SXDOTRQ7X7K" }
  }
  mock_data "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:222222222222:listener/app/mock/0000000000000000/0000000000000000" }
  }
  mock_data "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:222222222222:targetgroup/mock/0000000000000000", name = "mock" }
  }
  mock_data "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-bucket", id = "mock-bucket" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:222222222222:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_kms_replica_key" {
    defaults = { arn = "arn:aws:kms:us-west-2:222222222222:key/00000000-0000-0000-0000-000000000000" }
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
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::222222222222:role/mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-bucket" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:222222222222:log-group:mock" }
  }
  mock_resource "aws_backup_vault" {
    defaults = { arn = "arn:aws:backup:us-east-1:222222222222:backup-vault:mock" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:us-east-1:222222222222:regional/webacl/mock/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:222222222222:function:mock" }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

mock_provider "archive" {}

variables {
  config_file = "/nonexistent"
}

run "files_plan" {
  command = plan
}
