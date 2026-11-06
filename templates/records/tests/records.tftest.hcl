mock_provider "aws" {
  alias = "dns"
}

mock_provider "aws" {}

override_data {
  target = data.aws_route53_zone.zones["example.com|false"]
  values = { zone_id = "Z0PUBLIC" }
}

override_data {
  target = data.aws_route53_zone.zones["corp.internal|true"]
  values = { zone_id = "Z0HUBPRIVATE" }
}

override_data {
  target = data.aws_route53_zone.own_zones["operations.corp.internal"]
  values = { zone_id = "Z0OPERATIONS" }
}

override_data {
  target = data.aws_lb.load_balancers["external"]
  values = { dns_name = "operations-external-123.us-east-2.elb.amazonaws.com", zone_id = "Z3AADJGX6KTTL2" }
}

override_data {
  target = data.aws_instance.servers["grafana-01"]
  values = { private_ip = "10.42.228.70" }
}

variables {
  environment = "operations"
  config_path = "../../tests/config"
}

run "alias_address_and_cname" {
  command = plan

  variables {
    config_dir = "tests/records"
  }

  assert {
    condition     = toset(keys(local.records)) == toset(["api", "grafana", "sql"]) && length(local.problems) == 0
    error_message = "One record per file, named after the file."
  }

  assert {
    condition     = jsonencode(local.record.api.alias) == jsonencode({ name = "operations-external-123.us-east-2.elb.amazonaws.com", zone_id = "Z3AADJGX6KTTL2", evaluate_target_health = true }) && local.record.api.zone_id == "Z0PUBLIC" && !local.records.api.own
    error_message = "alias names a load balancer of the environment for both its name and zone_id; zone_id names a public domain, written with the hub's account."
  }

  assert {
    condition     = jsonencode(local.record.grafana.records) == jsonencode(["10.42.228.70"]) && local.record.grafana.zone_id == "Z0OPERATIONS" && local.records.grafana.own
    error_message = "An A record may name a server for its private address; the environment's own zone is written with its own account."
  }

  assert {
    condition     = local.record.sql.type == "CNAME" && local.record.sql.ttl == 60 && jsonencode(local.record.sql.records) == jsonencode(["sqlserver-01.operations.corp.internal"]) && local.record.sql.zone_id == "Z0HUBPRIVATE"
    error_message = "A CNAME is written as given, in the hub's private zone."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.names == {}
    error_message = "Without files, no records."
  }
}

run "ids_pass_through" {
  command = plan

  variables {
    config_dir  = "tests/own-zones"
    environment = "staging"
  }

  override_data {
    target = data.aws_route53_zone.own_zones["staging.corp.internal"]
    values = { zone_id = "Z0STAGING" }
  }

  assert {
    condition     = local.record.sso.alias.name == "external-123.us-east-2.elb.amazonaws.com" && local.record.sso.alias.zone_id == "Z3AADJGX6KTTL2" && !local.record.sso.alias.evaluate_target_health && length(data.aws_lb.load_balancers) == 0
    error_message = "An alias to a DNS name and a hosted zone id is written as given, with nothing looked up."
  }

  assert {
    condition     = jsonencode(local.record.grafana.records) == jsonencode(["10.43.228.70"]) && length(data.aws_instance.servers) == 0
    error_message = "An address is written as given."
  }
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition     = contains(local.problems, "api.yml: keys are zone_id, name, type, ttl, records, alias, as aws_route53_record takes them")
    error_message = "zone: and load_balancer: are not arguments of aws_route53_record."
  }

  expect_failures = [output.names]
}

run "refuses_a_record_without_a_zone" {
  command = plan

  variables {
    config_dir = "tests/no-zone"
  }

  assert {
    condition     = contains(local.problems, "api.yml: zone_id is required: the hosted zone's name, such as example.com, or its id")
    error_message = "There is no default zone."
  }

  expect_failures = [output.names]
}
