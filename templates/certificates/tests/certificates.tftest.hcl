# certificates.yml turned into certificates, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

override_data {
  target = module.acm_certificate.data.aws_route53_zone.zones["example.com"]
  values = { zone_id = "Z0EXAMPLE" }
}

run "grafana" {
  command = plan

  variables {
    config_dir = "tests/certificates"
  }

  assert {
    condition     = local.certificates.grafana.domain == "grafana.example.com"
    error_message = "One certificate per entry in the file."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.arns == {}
    error_message = "Without certificates.yml, no certificates."
  }
}
