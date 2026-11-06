mock_provider "aws" {}

mock_provider "aws" {
  alias = "us_east_1"
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
  target = data.aws_cloudfront_response_headers_policy.policies["Managed-SecurityHeadersPolicy"]
  values = { id = "67f7725c-6f97-4210-82d7-5512b31e9d03" }
}

override_data {
  target = module.web_acls.data.aws_s3_bucket.logs[0]
  values = { arn = "arn:aws:s3:::aws-waf-logs-111111111111-us-east-1" }
}

run "media_assets" {
  command = plan

  variables {
    config_dir = "tests/stack"
  }

  assert {
    condition     = length(local.problems) == 0 && toset(keys(output.distributions)) == toset(["media-assets"]) && toset(keys(module.web_acls.arns)) == toset(["media-assets"])
    error_message = "One distribution per file in distribution/, one CLOUDFRONT web ACL per file in web-acl/."
  }

  assert {
    condition     = local.resolved["media-assets"].origin[0].domain_name == "example-media-assets.s3.us-east-2.amazonaws.com" && local.resolved["media-assets"].viewer_certificate.acm_certificate_arn == "arn:aws:acm:us-east-1:111111111111:certificate/example"
    error_message = "An origin's domain_name is found from its bucket's name, and the certificate from its domain."
  }

  assert {
    condition     = toset(keys(data.aws_cloudfront_cache_policy.policies)) == toset(["Managed-CachingOptimized"]) && local.resolved["media-assets"].default_cache_behavior.response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
    error_message = "Cache and response headers policies are found by name."
  }
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "assets.yml: a distribution's file is in distribution/, a web ACL's in web-acl/"),
      contains(local.problems, "media-assets.yml: keys are aliases, origin, default_cache_behavior, price_class, viewer_certificate, web_acl_id, as aws_cloudfront_distribution takes them"),
      contains(local.problems, "media-assets.yml: price_class is needed (PriceClass_100, PriceClass_200 or PriceClass_All)"),
      contains(local.problems, "media-assets.yml: web_acl_id missing is not a web ACL in this stack (a file named web-acl/missing.yml), nor an ARN"),
    ])
    error_message = "origin_bucket, certificate and waf are not arguments, and nothing is filled in for a file."
  }

  expect_failures = [output.distributions]
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.distributions == {} && output.web_acls == {}
    error_message = "Without files, no distributions."
  }
}
