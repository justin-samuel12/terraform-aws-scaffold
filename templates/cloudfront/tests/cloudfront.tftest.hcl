# Distribution files turned into distributions, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

mock_provider "aws" {
  alias = "us_east_1"
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_s3_bucket.origins["example-media-assets"]
  values = { bucket_regional_domain_name = "example-media-assets.s3.us-east-2.amazonaws.com" }
}

override_data {
  target = data.aws_acm_certificate.certificates["assets.example.com"]
  values = { arn = "arn:aws:acm:us-east-1:111111111111:certificate/example" }
}

override_data {
  target = data.aws_s3_bucket.waf_logs[0]
  values = { arn = "arn:aws:s3:::aws-waf-logs-111111111111-us-east-1" }
}

run "media_assets" {
  command = plan

  variables {
    config_dir = "tests/distributions"
  }

  assert {
    condition     = toset(keys(output.distributions)) == toset(["media-assets"])
    error_message = "One distribution per file."
  }

  assert {
    condition     = toset(keys(module.waf_web_acl)) == toset(["media-assets"])
    error_message = "waf: true gives the distribution a CLOUDFRONT web ACL, in us-east-1."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.distributions == {}
    error_message = "Without files, no distributions."
  }
}
