variables {
  dir         = "tests/blueprints"
  label       = "blueprints/test"
  body        = "service"
  example     = "web/v1"
  choices     = { instance_type = "instance_types" }
  environment = "staging"
  region      = "us-east-2"
}

run "expands" {
  command = plan

  variables {
    files = {
      shop  = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["shop.example.com"] } } }, image = "shop:1", cpu = 2048, memory = 4096, health_check = { path = "/ready" } }
      plain = { count = 1, anything = "kept" }
    }
  }

  assert {
    condition     = length(output.problems) == 0 && output.files.plain.anything == "kept"
    error_message = "A usable file on a blueprint, and one without, which passes through untouched."
  }

  assert {
    condition     = output.files.shop.listener_rule.priority == 1100 && output.files.shop.listener_rule.listener_arn == "public/443" && jsonencode(output.files.shop.listener_rule.condition.host_header.values) == jsonencode(["shop.example.com"]) && output.files.shop.tags.Name == "staging-shop-us-east-2"
    error_message = "The app's listener_rule is kept whole; {app}, {environment} and {region} are filled in."
  }

  assert {
    condition     = output.files.shop.image == "shop:1" && !can(output.files.shop.blueprint)
    error_message = "A required value is the file's own; blueprint itself is not left behind."
  }

  assert {
    condition     = output.files.shop.health_check.path == "/ready" && output.files.shop.health_check.matcher == "200"
    error_message = "A map the app changes keeps the blueprint's other keys."
  }

  assert {
    condition     = output.files.shop.cpu == 2048 && output.files.shop.memory == 4096 && output.files.shop.count == 2
    error_message = "An allowed argument the app sets replaces the blueprint's; one it leaves is the blueprint's."
  }
}

run "the_blueprints_values_by_default" {
  command = plan

  variables {
    files = { shop = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["shop.example.com"] } } }, image = "shop:1" } }
  }

  assert {
    condition     = output.files.shop.cpu == 512 && output.files.shop.memory == 1024 && output.files.shop.instance_type == "t3.small"
    error_message = "Without a cpu, memory or instance type of its own, an app gets the blueprint's."
  }
}

run "refuses" {
  command = plan

  variables {
    files = {
      drifted = { blueprint = "web/v1", listener_rule = {}, image = "x", tier = "public", instance_type = "m7i.24xlarge", sizes = "huge" }
      unknown = { blueprint = "web/v3" }
      badref  = { blueprint = "web" }
      broken  = { blueprint = "database/v1" }
      missing = { blueprint = "web/v1" }
    }
  }

  assert {
    condition = alltrue([
      contains(output.problems, "drifted.yml: tier is set by blueprint web/v1; an app on it may set count, instance_type, cpu, memory, health_check, members.*.tags"),
      contains(output.problems, "drifted.yml: instance_type m7i.24xlarge is not one blueprint web/v1 offers: t3.small, t3.large"),
      contains(output.problems, "blueprints/test/database/v1.yml: instance_types needs allowed and a default that is one of them"),
      contains(output.problems, "blueprints/test/database/v1.yml: environments.staging may set only instance_types"),
      contains(output.problems, "drifted.yml: sizes is set by blueprint web/v1; an app on it may set count, instance_type, cpu, memory, health_check, members.*.tags"),
      contains(output.problems, "blueprints/test/database/v1.yml: a blueprint holds description, allows, adds, requires, environments, service, instance_types"),
      contains(output.problems, "unknown.yml: blueprint web/v3 not found: blueprints/test/web/ has v1"),
      contains(output.problems, "badref.yml: blueprint web is <name>/v<number>, such as web/v1"),
      contains(output.problems, "blueprints/test/database/v1.yml: it needs service: the settings every app on it gets"),
      contains(output.problems, "missing.yml: blueprint web/v1 needs listener_rule"),
      contains(output.problems, "missing.yml: blueprint web/v1 needs image"),
    ])
    error_message = "Each kind of mistake is named, with what would be right."
  }
}

run "added_groups" {
  command = plan

  variables {
    files = {
      plain   = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["a.example.com"] } } }, image = "a:1" }
      renamed = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1110, condition = { host_header = { values = ["b.example.com"] } } }, image = "b:1", vpc_security_group_ids = ["renamed-files", "web"] }
    }
  }

  assert {
    condition     = length(output.problems) == 0 && output.files.plain.vpc_security_group_ids == ["web"]
    error_message = "Without groups of its own, an app's groups are the blueprint's."
  }

  assert {
    condition     = output.files.renamed.vpc_security_group_ids == ["web", "renamed-files"]
    error_message = "Its groups are added to the blueprint's, never replace them, and a group named twice counts once."
  }
}

run "refuses_groups_not_a_list" {
  command = plan

  variables {
    files = {
      wrong = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["a.example.com"] } } }, image = "a:1", vpc_security_group_ids = "renamed-files" }
    }
  }

  assert {
    condition     = contains(output.problems, "wrong.yml: vpc_security_group_ids is a list, added to blueprint web/v1's")
    error_message = "Groups that are not a list are named."
  }
}

run "a_blueprint_without_a_rule" {
  command = plan

  variables {
    files = { ledger = { blueprint = "bare/v1", instance_class = "db.m6i.xlarge", vpc_security_group_ids = ["ledger-database"] } }
  }

  assert {
    condition     = length(output.problems) == 0 && output.files.ledger.engine == "sqlserver-se" && output.files.ledger.instance_class == "db.m6i.xlarge" && output.files.ledger.vpc_security_group_ids == ["ledger-database"]
    error_message = "A blueprint with no listener rule expands as well as one with it."
  }
}

run "production_chooses_from_its_own" {
  command = plan

  variables {
    environment = "production"
    files = {
      plain  = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["a.example.com"] } } }, image = "a:1" }
      larger = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1110, condition = { host_header = { values = ["b.example.com"] } } }, image = "b:1", instance_type = "m7g.large" }
      burst  = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1120, condition = { host_header = { values = ["c.example.com"] } } }, image = "c:1", instance_type = "t3.large" }
    }
  }

  assert {
    condition     = output.files.plain.instance_type == "m7i.large" && output.files.larger.instance_type == "m7g.large" && output.files.plain.cpu == 512
    error_message = "In production an app gets production's default, or chooses from production's list; what it does not override stays the blueprint's."
  }

  assert {
    condition     = output.problems == ["burst.yml: instance_type t3.large is not one blueprint web/v1 offers in production: m7i.large, m7g.large"]
    error_message = "An instance type allowed elsewhere is refused in production, which names its own list."
  }
}

run "tags_merge" {
  command = plan

  variables {
    files = {
      shop = {
        blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["a.example.com"] } } }, image = "a:1"
        tags      = { WorkloadType = "['applications','services']", Certificates = "['staging.example.com']" }
        members   = { shop-01 = { tags = { DNS = "shop01" } } }
      }
      lone = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1110, condition = { host_header = { values = ["b.example.com"] } } }, image = "b:1", members = { lone-01 = { subnet = "data-az1" } } }
    }
  }

  assert {
    condition     = output.files.shop.tags == { Name = "staging-shop-us-east-2", ServerRole = "appsvc", WorkloadType = "['applications','services']", Certificates = "['staging.example.com']" }
    error_message = "An app's tags merge over the blueprint's: its own added, the same key given its value, the rest kept."
  }

  assert {
    condition     = output.files.shop.members.shop-01.tags.DNS == "shop01" && output.problems == ["lone.yml: members.lone-01.subnet is set by blueprint web/v1; an app on it may set count, instance_type, cpu, memory, health_check, members.*.tags"]
    error_message = "members.*.tags allows a tag for any one server, and nothing else under members."
  }
}

run "added_inside_a_block" {
  command = plan

  variables {
    files = {
      plain = { blueprint = "task/v1" }
      more  = { blueprint = "task/v1", network_configuration = { security_groups = ["orders-api", "ecs-services"] } }
    }
  }

  assert {
    condition     = length(output.problems) == 0 && jsonencode(output.files.plain.network_configuration.security_groups) == jsonencode(["ecs-services"])
    error_message = "Without groups of its own, an app's groups are the blueprint's."
  }

  assert {
    condition     = jsonencode(output.files.more.network_configuration.security_groups) == jsonencode(["ecs-services", "orders-api"]) && jsonencode(output.files.more.network_configuration.subnets) == jsonencode(["private-az1", "private-az2"])
    error_message = "A list named parent.key in adds is added to the blueprint's inside that block, and the block's other keys stay the blueprint's."
  }
}

run "refuses_a_nested_addition_not_a_list" {
  command = plan

  variables {
    files = {
      wrong = { blueprint = "task/v1", network_configuration = { security_groups = "orders-api" } }
    }
  }

  assert {
    condition     = contains(output.problems, "wrong.yml: network_configuration.security_groups is a list, added to blueprint task/v1's")
    error_message = "A nested addition that is not a list is named."
  }
}

run "a_released_version_never_changes" {
  command = plan

  variables {
    dir   = "tests/versions-changed"
    files = { shop = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["shop.example.com"] } } }, image = "shop:1" } }
  }

  assert {
    condition     = anytrue([for p in output.problems : startswith(p, "blueprints/test/web/v1.yml changed after it was released") && strcontains(p, "put the change in web/v2.yml and release that")])
    error_message = "Editing a released version is refused, and the message names the next version to put the change in: ${jsonencode(output.problems)}."
  }
}

run "an_unreleased_version_is_refused" {
  command = plan

  variables {
    dir   = "tests/versions-unreleased"
    files = { shop = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["shop.example.com"] } } }, image = "shop:1" } }
  }

  assert {
    condition     = anytrue([for p in output.problems : startswith(p, "shop.yml: blueprint web/v1 is not released.") && strcontains(p, "sha256: ")])
    error_message = "An app cannot use a version nobody released; the message gives the line to release it with."
  }
}

run "a_deprecated_version_still_works_and_warns" {
  command = plan

  variables {
    dir   = "tests/versions-deprecated"
    files = { shop = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["shop.example.com"] } } }, image = "shop:1" } }
  }

  assert {
    condition     = length(output.problems) == 0 && output.files.shop.memory == 1024
    error_message = "An app on a deprecated version keeps working exactly as before."
  }

  assert {
    condition     = output.warnings == ["shop.yml: blueprint web/v1 is deprecated; move the app to web/v2 (docs/blueprints.md#moving-an-app-to-a-new-version): v2 doubles the memory; set memory to keep the old size"]
    error_message = "It is told where to move, and what changes when it does."
  }
}

run "moving_to_the_new_version" {
  command = plan

  variables {
    dir   = "tests/versions-deprecated"
    files = { shop = { blueprint = "web/v2", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["shop.example.com"] } } }, image = "shop:1", memory = 1024 } }
  }

  assert {
    condition     = length(output.problems) == 0 && length(output.warnings) == 0 && output.files.shop.memory == 1024
    error_message = "Moving names the new version and, where the app wants the old behavior, sets it: here the memory it had."
  }
}

run "a_retired_version_is_refused" {
  command = plan

  variables {
    dir   = "tests/versions-retired"
    files = { shop = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["shop.example.com"] } } }, image = "shop:1" } }
  }

  assert {
    condition     = contains(output.problems, "shop.yml: blueprint web/v1 is retired; move the app to web/v2 (docs/blueprints.md#moving-an-app-to-a-new-version)")
    error_message = "A retired version can no longer be planned, and the message says where to go."
  }
}

run "platform_tags_cannot_be_set_in_a_file" {
  command = plan

  variables {
    files = { shop = { blueprint = "web/v1", listener_rule = { listener_arn = "public/443", priority = 1100, condition = { host_header = { values = ["shop.example.com"] } } }, image = "shop:1", tags = { Environment = "production", Owner = "shop-team" } } }
  }

  assert {
    condition     = contains(output.problems, "shop.yml: tags.Environment is set by the platform from where the stack is, never in a file: the pipeline's permissions and every lookup rely on it")
    error_message = "A file cannot retag its resources into another environment."
  }

  assert {
    condition     = length(output.problems) == 1
    error_message = "Other tags stay the app's own: ${jsonencode(output.problems)}."
  }
}

run "every_released_compute_blueprint_is_intact" {
  command = plan

  variables {
    dir   = "../../blueprints/compute"
    label = "blueprints/compute"
    body  = "group"
    files = {}
  }

  assert {
    condition     = length(output.problems) == 0
    error_message = "Every version in blueprints/compute/versions.yml is exactly the file that was released: ${jsonencode(output.problems)}."
  }
}

run "every_released_containers_blueprint_is_intact" {
  command = plan

  variables {
    dir   = "../../blueprints/containers"
    label = "blueprints/containers"
    files = {}
  }

  assert {
    condition     = length(output.problems) == 0
    error_message = "Every version in blueprints/containers/versions.yml is exactly the file that was released: ${jsonencode(output.problems)}."
  }
}

run "every_released_databases_blueprint_is_intact" {
  command = plan

  variables {
    dir   = "../../blueprints/databases"
    label = "blueprints/databases"
    body  = "database"
    files = {}
  }

  assert {
    condition     = length(output.problems) == 0
    error_message = "Every version in blueprints/databases/versions.yml is exactly the file that was released: ${jsonencode(output.problems)}."
  }
}
