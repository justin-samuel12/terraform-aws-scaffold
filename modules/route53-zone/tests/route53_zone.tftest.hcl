mock_provider "aws" {}

variables {
  public  = ["example.com"]
  private = { "internal.example.com" = "vpc-hub" }
}

run "zones" {
  command = plan

  assert {
    condition     = aws_route53_zone.public["example.com"].name == "example.com" && length(aws_route53_zone.public["example.com"].vpc) == 0
    error_message = "A public zone has no VPC."
  }

  assert {
    condition     = one(aws_route53_zone.private["internal.example.com"].vpc).vpc_id == "vpc-hub"
    error_message = "A private zone is created with the hub's VPC; the others associate themselves."
  }
}

run "rejects_bad_name" {
  command = plan

  variables {
    public = ["Example.COM"]
  }

  expect_failures = [var.public]
}
