mock_provider "aws" {}

variables {
  name    = "media-assets"
  aliases = ["assets.example.com"]
  origin = [
    { origin_id = "example-media-assets", domain_name = "example-media-assets.s3.us-east-2.amazonaws.com" },
  ]
  default_cache_behavior = {
    target_origin_id           = "example-media-assets"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03"
  }
  price_class = "PriceClass_100"
  viewer_certificate = {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:111111111111:certificate/example"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

run "private_origin_https_only" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.distribution.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https" && aws_cloudfront_distribution.distribution.price_class == "PriceClass_100"
    error_message = "The distribution is what it was given."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.distribution.viewer_certificate).minimum_protocol_version == "TLSv1.2_2021" && one(aws_cloudfront_distribution.distribution.viewer_certificate).ssl_support_method == "sni-only"
    error_message = "TLS 1.2 or later, with the certificate it was given."
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.origin.signing_behavior == "always"
    error_message = "The bucket stays private: CloudFront signs every request."
  }

  assert {
    condition     = jsonencode(output.bucket_policy_statement.Resource) == jsonencode(["arn:aws:s3:::example-media-assets/*"])
    error_message = "The bucket policy statement covers the origin's bucket."
  }
}

run "rejects_certificate_outside_us_east_1" {
  command = plan

  variables {
    viewer_certificate = { acm_certificate_arn = "arn:aws:acm:us-east-2:111111111111:certificate/example", ssl_support_method = "sni-only", minimum_protocol_version = "TLSv1.2_2021" }
  }

  expect_failures = [var.viewer_certificate]
}

run "rejects_old_tls" {
  command = plan

  variables {
    viewer_certificate = { acm_certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/example", ssl_support_method = "sni-only", minimum_protocol_version = "TLSv1_2016" }
  }

  expect_failures = [var.viewer_certificate]
}

run "rejects_plain_http_viewers" {
  command = plan

  variables {
    default_cache_behavior = {
      target_origin_id       = "example-media-assets"
      viewer_protocol_policy = "allow-all"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true
      cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    }
  }

  expect_failures = [var.default_cache_behavior]
}

run "rejects_aliases_without_certificate" {
  command = plan

  variables {
    viewer_certificate = { cloudfront_default_certificate = true }
  }

  expect_failures = [aws_cloudfront_distribution.distribution]
}
