# Web ACL files turned into web ACLs, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

override_data {
  target = data.aws_s3_bucket.logs[0]
  values = { arn = "arn:aws:s3:::aws-waf-logs-111111111111-us-east-2" }
}

override_data {
  target = data.aws_lb.load_balancers["web"]
  values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:loadbalancer/app/web/abc" }
}

variables {
  region = "us-east-2"
}

run "web" {
  command = plan

  variables {
    config_dir = "tests/acls"
  }

  assert {
    condition     = local.web_acls.web.rate_limit == 1000 && local.web_acls.web.load_balancers == tolist(["web"])
    error_message = "One web ACL per file, with its rate limit and load balancers."
  }

  assert {
    condition     = toset(keys(output.arns)) == toset(["web"])
    error_message = "The web ACL is built."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.arns == {}
    error_message = "Without files, no web ACLs."
  }
}
