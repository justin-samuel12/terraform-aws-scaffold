# Database files turned into databases, against a mocked AWS -- docs/data.md.
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
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/rds-directory-operations-us-east-2" }
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
    condition     = local.custom_versions["16.00.4185.3.dbamp-v1"].file == "dbamp" && length(module.directory_role) == 1 && length(module.monitoring_role) == 1
    error_message = "salesforce-sync's version is the one engine-versions/dbamp.yml defines; etl's directory gets its role."
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
      "express-multi-az.yml: SQL Server Express cannot be Multi-AZ",
      "aurora-key-on-rds.yml: instances is for Aurora, not RDS",
      "custom-with-options.yml: options is for RDS for SQL Server, not RDS Custom for SQL Server",
      "unknown-edition.yml: engine must be one of",
      "undefined-version.yml: engine_version 16.00.4185.3.nowhere-v1 is a version of our own, but no file in engine-versions/ defines it",
      "ssis-without-ad.yml: SSIS signs people in through Windows",
      "ssas-on-2022.yml: SSAS does not run on SQL Server 16.00",
      "serverless-without-capacity.yml: Serverless v2 (db.serverless) needs serverlessv2_scaling_configuration",
      "storage-on-aurora.yml: allocated_storage is for RDS, RDS for SQL Server, RDS Custom for SQL Server, not Aurora",
      "half-a-domain.yml: a self-managed domain needs all of",
      "developer-included.yml: Developer edition comes only from our own media",
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
    config_dir = "../../examples/us-east-1/development/databases"
  }

  assert {
    condition     = { for name, d in output.databases : name => d.kind } == { dashboards = "rds", billing = "sqlserver", salesforce-sync = "rds-custom", reporting = "aurora", jobs = "aurora" }
    error_message = "Every example database plans."
  }
}
