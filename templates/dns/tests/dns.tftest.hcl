# zones.yml and config's private zones turned into hosted zones, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

variables {
  config_path = "../../tests/config"
}

run "public_zones" {
  command = plan

  variables {
    config_dir = "tests/zones"
  }

  assert {
    condition     = local.public == toset(["example.com"]) && toset(keys(output.public)) == toset(["example.com"])
    error_message = "One public zone per name in zones.yml."
  }

  assert {
    condition     = output.private == {}
    error_message = "No private zones until config/global.yml lists them."
  }
}
