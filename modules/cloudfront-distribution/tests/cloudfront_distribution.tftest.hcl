# What the module builds and refuses, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

variables {
  name            = "media-assets"
  aliases         = ["assets.example.com"]
  origin_bucket   = { name = "example-media-assets", regional_domain_name = "example-media-assets.s3.us-east-2.amazonaws.com" }
  certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/example"
}

run "private_origin_https_only" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.distribution.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Viewers are always sent to HTTPS."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.distribution.viewer_certificate).minimum_protocol_version == "TLSv1.2_2021"
    error_message = "TLS 1.2 or later."
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.origin.signing_behavior == "always"
    error_message = "The bucket stays private: CloudFront signs every request."
  }
}

run "rejects_certificate_outside_us_east_1" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-east-2:111111111111:certificate/example"
  }

  expect_failures = [var.certificate_arn]
}

run "rejects_aliases_without_certificate" {
  command = plan

  variables {
    certificate_arn = null
  }

  expect_failures = [aws_cloudfront_distribution.distribution]
}
