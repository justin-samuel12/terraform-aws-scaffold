mock_provider "aws" {
  alias = "dns"
}

mock_provider "aws" {}

override_data {
  target = data.aws_route53_zone.zones["example.com"]
  values = { zone_id = "Z0EXAMPLE" }
}

variables {
  certificates = {
    grafana = { domain_name = "grafana.example.com", subject_alternative_names = ["metrics.example.com"], validation_method = "DNS", key_algorithm = "EC_prime256v1", validation_zone = "example.com" }
  }
}

run "dns_validated" {
  command = plan

  assert {
    condition     = aws_acm_certificate.certificates["grafana"].validation_method == "DNS" && aws_acm_certificate.certificates["grafana"].domain_name == "grafana.example.com" && aws_acm_certificate.certificates["grafana"].key_algorithm == "EC_prime256v1"
    error_message = "The certificate takes the arguments it was given."
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
      grafana = { domain_name = "grafana.other.com", validation_method = "DNS", key_algorithm = "RSA_2048", validation_zone = "example.com" }
    }
  }

  expect_failures = [var.certificates]
}
