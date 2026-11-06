mock_provider "aws" {
  mock_data "aws_security_group" {
    defaults = { id = "sg-database" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/operations-sqlserver-backups" }
  }
}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-operations" }
}

override_data {
  target = data.aws_subnets.data[0]
  values = { ids = ["subnet-data-1", "subnet-data-2", "subnet-data-3"] }
}

override_data {
  target = data.aws_security_group.groups["database-mysql"]
  values = { id = "sg-database-mysql" }
}

override_data {
  target = data.aws_kms_key.data[0]
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
}

override_data {
  target = module.monitoring_role[0].data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  environment = "operations"
}

run "zabbix" {
  command = plan

  variables {
    config_dir = "tests/databases"
  }

  assert {
    condition     = toset(keys(output.databases)) == toset(["zabbix"])
    error_message = "One database per file."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.databases == {}
    error_message = "Without files, no databases and no monitoring role."
  }
}

run "every_kind" {
  command = plan

  variables {
    config_dir = "tests/kinds"
  }

  assert {
    condition     = { for name, d in output.databases : name => d.kind } == { billing = "sqlserver", etl = "sqlserver", lab = "sqlserver", salesforce-sync = "rds-custom", reporting = "aurora", events = "aurora", zabbix = "rds" }
    error_message = "The engine decides the kind: RDS, RDS for SQL Server, RDS Custom or Aurora."
  }

  assert {
    condition     = output.databases["billing"].port == 1433 && output.databases["salesforce-sync"].port == 1433 && output.databases["reporting"].port == 5432 && output.databases["events"].port == 3306
    error_message = "SQL Server on 1433, Aurora PostgreSQL on 5432, Aurora MySQL on 3306."
  }

  assert {
    condition     = output.rds_custom_instance_profile == "AWSRDSCustom-operations-us-east-2" && aws_iam_role.rds_custom[0].name == "AWSRDSCustom-operations-us-east-2" && endswith(aws_iam_role_policy_attachment.rds_custom[0].policy_arn, ":policy/AmazonRDSCustomInstanceProfileRolePolicy")
    error_message = "One RDS Custom instance profile for the environment and region, named as AWS requires, with AWS's policy for it."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.rds_custom[0].policy, "arn:aws:kms:us-east-2:111111111111:key/mrk-data")
    error_message = "RDS Custom's servers may use the environment's data key."
  }

  assert {
    condition     = local.custom_versions["16.00.4185.3.dbamp-v1"].file == "dbamp" && length(module.monitoring_role) == 1
    error_message = "salesforce-sync's version is the one engine-versions/dbamp.yml defines."
  }

  assert {
    condition     = jsonencode([for o in local.option_args.billing : o.option_name]) == jsonencode(["SQLSERVER_BACKUP_RESTORE", "TDE", "SSRS"]) && local.option_args.billing[0].option_settings[0].value == "arn:aws:iam::111111111111:role/operations-sqlserver-backups"
    error_message = "Options as the file lists them; IAM_ROLE_ARN names a role, found by its name."
  }

  assert {
    condition     = jsonencode(local.option_args.billing[2].vpc_security_group_memberships) == jsonencode(["sg-database"]) && local.option_args.billing[2].port == 8443 && local.option_args.billing[1].vpc_security_group_memberships == null
    error_message = "An option's groups are named and looked up; one that names none gets none."
  }

  assert {
    condition     = toset(local.group_names) == toset(["billing-database", "database-mysql", "reporting-database", "salesforce-sync-database"])
    error_message = "Groups named in files are looked up; an sg- ID is not."
  }

  assert {
    condition     = output.databases["billing"].reader_endpoint == null && output.databases["zabbix"].reader_endpoint == null
    error_message = "Only Aurora has a reader endpoint."
  }
}

run "refusals" {
  command = plan

  variables {
    config_dir = "tests/refused"
  }

  expect_failures = [output.databases]

  assert {
    condition = alltrue([for p in [
      "aurora-key-on-rds.yml: count is for Aurora, not RDS",
      "custom-with-options.yml: option is for RDS for SQL Server, not RDS Custom for SQL Server",
      "unknown-edition.yml: engine must be one of",
      "undefined-version.yml: engine_version 16.00.4185.3.nowhere-v1 is a version of our own, but no file in engine-versions/ defines it",
      "serverless-without-capacity.yml: Serverless v2 (instance_class db.serverless) needs serverlessv2_scaling_configuration",
      "storage-on-aurora.yml: allocated_storage is for RDS, RDS for SQL Server, RDS Custom for SQL Server, not Aurora",
      "domain-without-role.yml: domain and domain_iam_role_name go together",
      "old-keys.yml: security_groups is not an argument here",
      "old-keys.yml: options is not an argument here",
      "option-settings-by-name.yml: an option takes option_name, port, version, vpc_security_group_memberships, option_settings",
      "custom-without-password-version.yml: needs password_wo_version",
    ] : length([for q in local.problems : q if startswith(q, p)]) == 1])
    error_message = "Each refused file says what is wrong with it."
  }

  assert {
    condition     = length(module.rds_instance) == 0 && length(module.rds_cluster) == 0
    error_message = "A refused file builds nothing."
  }
}

run "examples" {
  command = plan

  variables {
    config_dir     = "../../examples/us-east-1/development/databases/config"
    blueprints_dir = "../../blueprints/databases"
  }

  assert {
    condition     = { for name, d in output.databases : name => d.kind } == { dashboards = "rds", billing = "sqlserver", salesforce-sync = "rds-custom", reporting = "aurora", jobs = "aurora", ledger = "sqlserver" }
    error_message = "Every example database plans."
  }
}

run "on_blueprints" {
  command = plan

  variables {
    config_dir     = "tests/on-blueprints"
    blueprints_dir = "../../blueprints/databases"
  }

  assert {
    condition     = length(local.problems) == 0 && local.kinds["billing"] == "sqlserver" && local.kinds["reporting"] == "aurora"
    error_message = "A SQL Server database and an Aurora cluster, both from blueprints, both usable."
  }

  assert {
    condition     = local.files["billing"].instance_class == "db.m6i.xlarge" && local.files["billing"].allocated_storage == 200 && local.files["billing"].max_allocated_storage == 1000 && local.files["billing"].multi_az && local.files["billing"].engine_version == "16.00"
    error_message = "The database's own size, and the blueprint's version, Multi-AZ and storage ceiling."
  }

  assert {
    condition     = jsonencode([for o in local.files["billing"].option : o.option_name]) == jsonencode(["SQLSERVER_BACKUP_RESTORE", "TDE"]) && local.option_args.billing[0].option_settings[0].value == "arn:aws:iam::111111111111:role/operations-sqlserver-backups" && jsonencode(local.files["billing"].vpc_security_group_ids) == jsonencode(["billing-database"])
    error_message = "Native backups and TDE from the blueprint; the security group the database names."
  }

  assert {
    condition     = local.files["reporting"].engine == "aurora-postgresql" && local.files["reporting"].count == 2 && local.files["reporting"].instance_class == "db.r7g.large"
    error_message = "Aurora PostgreSQL as the blueprint gives it."
  }
}

run "blueprint_refusals" {
  command = plan

  variables {
    config_dir     = "tests/on-blueprints-refused"
    blueprints_dir = "../../blueprints/databases"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "billing.yml: instance_class db.x2iedn.32xlarge is not one blueprint sqlserver/v1 offers: db.m6i.large, db.m6i.xlarge, db.m6i.2xlarge, db.r6i.large, db.r6i.xlarge, db.r6i.2xlarge"),
      contains(local.problems, "billing.yml: multi_az is set by blueprint sqlserver/v1; an app on it may set instance_class, allocated_storage, max_allocated_storage"),
      contains(local.problems, "reporting.yml: blueprint aurora-postgres/v1 needs vpc_security_group_ids"),
    ])
    error_message = "A size the blueprint does not offer, turning off Multi-AZ, and a database with no group of its own are each refused."
  }

  expect_failures = [output.databases]
}
