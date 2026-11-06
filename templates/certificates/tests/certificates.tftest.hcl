mock_provider "aws" {
  alias = "dns"
}

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
    condition     = toset(keys(local.certificates)) == toset(["grafana"]) && length(local.problems) == 0
    error_message = "One certificate per file, named after the file."
  }

  assert {
    condition     = jsonencode(local.certificates.grafana) == jsonencode({ domain_name = "grafana.example.com", subject_alternative_names = ["metrics.example.com"], validation_method = "DNS", key_algorithm = "RSA_2048", tags = { Team = "observability" }, validation_zone = "example.com" })
    error_message = "The file's arguments are the certificate's, as written."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.arns == {}
    error_message = "Without files, no certificates."
  }
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition     = contains(local.problems, "grafana.yml: keys are domain_name, subject_alternative_names, validation_method, key_algorithm, tags, route53_record: aws_acm_certificate's arguments and the public zone its validation records go in")
    error_message = "zone: is not a key."
  }

  assert {
    condition     = contains(local.problems, "grafana.yml: validation_method is DNS, the only method that renews by itself") && contains(local.problems, "grafana.yml: key_algorithm is one of RSA_2048, RSA_3072, RSA_4096, EC_prime256v1, EC_secp384r1, EC_secp521r1")
    error_message = "Nothing is assumed: validation_method and key_algorithm are written."
  }

  expect_failures = [output.arns]
}
