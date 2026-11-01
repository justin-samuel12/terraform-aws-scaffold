# What the module builds and refuses, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

override_data {
  target = data.aws_route53_zone.zones["example.com"]
  values = { zone_id = "Z0EXAMPLE" }
}

variables {
  certificates = {
    grafana = { domain = "grafana.example.com", alternative_names = ["metrics.example.com"], zone = "example.com" }
  }
}

run "dns_validated" {
  command = plan

  assert {
    condition     = aws_acm_certificate.certificates["grafana"].validation_method == "DNS" && aws_acm_certificate.certificates["grafana"].domain_name == "grafana.example.com"
    error_message = "Certificates are validated through DNS, so they renew by themselves."
  }

  assert {
    condition     = toset(keys(aws_route53_record.validation)) == toset(["grafana/grafana.example.com", "grafana/metrics.example.com"])
    error_message = "One validation record per name on the certificate."
  }
}

run "rejects_a_name_outside_its_zone" {
  command = plan

  variables {
    certificates = {
      grafana = { domain = "grafana.other.com", zone = "example.com" }
    }
  }

  expect_failures = [var.certificates]
}
