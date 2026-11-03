# What the module builds and refuses, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

variables {
  name                = "orders"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t4g.medium"
  storage             = 200
  max_storage         = 1000
  subnet_ids          = ["subnet-data-1", "subnet-data-2", "subnet-data-3"]
  security_group_ids  = ["sg-database-mysql"]
  kms_key_arn         = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  monitoring_role_arn = "arn:aws:iam::111111111111:role/rds-monitoring-operations"
}

run "mysql" {
  command = plan

  assert {
    condition     = aws_db_instance.database.manage_master_user_password && !aws_db_instance.database.skip_final_snapshot && aws_db_instance.database.backup_retention_period == 35
    error_message = "A managed, rotated password; a final snapshot; backups kept 35 days."
  }

  assert {
    condition     = aws_db_parameter_group.database[0].family == "mysql8.0" && contains([for p in aws_db_parameter_group.database[0].parameter : p.name if p.value == "1"], "require_secure_transport")
    error_message = "Every connection must use TLS."
  }

  assert {
    condition     = aws_db_instance.database.tags.Backup == "standard" && aws_db_instance.database.deletion_protection && !aws_db_instance.database.publicly_accessible
    error_message = "In the backup plan, protected from deletion, never public."
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_group.database)) == toset(["error", "slowquery"]) && aws_cloudwatch_log_group.database["error"].retention_in_days == 365
    error_message = "Error and slow-query logs, kept a year."
  }
}

run "postgres" {
  command = plan

  variables {
    name           = "typebot"
    engine         = "postgres"
    engine_version = "16"
  }

  assert {
    condition     = aws_db_parameter_group.database[0].family == "postgres16" && contains([for p in aws_db_parameter_group.database[0].parameter : p.name], "rds.force_ssl")
    error_message = "PostgreSQL forces TLS too."
  }
}

run "rejects_unknown_engine" {
  command = plan

  variables {
    engine = "oracle-ee"
  }

  expect_failures = [var.engine]
}

run "sqlserver_standard" {
  command = plan

  variables {
    name                   = "billing"
    engine                 = "sqlserver-se"
    engine_version         = "16.00"
    instance_class         = "db.m6i.xlarge"
    timezone               = "Eastern Standard Time"
    character_set_name     = "SQL_Latin1_General_CP1_CI_AS"
    backup_restore_bucket  = "development-sqlserver-backups-111111111111-us-east-1"
    options                = { TDE = {}, SSRS = { port = 8443, settings = { MAX_MEMORY = "50" } } }
    domain_fqdn            = "corp.example.com"
    domain_ou              = "OU=RDS,DC=corp,DC=example,DC=com"
    domain_auth_secret_arn = "arn:aws:secretsmanager:us-east-1:111111111111:secret:rds-domain-join"
    domain_dns_ips         = ["10.10.0.10", "10.10.0.11"]
  }

  assert {
    condition     = aws_db_instance.database.license_model == "license-included" && aws_db_instance.database.port == 1433 && aws_db_instance.database.multi_az && !aws_db_instance.database.iam_database_authentication_enabled
    error_message = "License included, port 1433, Multi-AZ, and no IAM authentication, which SQL Server lacks."
  }

  assert {
    condition     = aws_db_parameter_group.database[0].family == "sqlserver-se-16.0" && contains([for p in aws_db_parameter_group.database[0].parameter : p.name], "rds.force_ssl")
    error_message = "SQL Server's family by edition and version, forcing TLS."
  }

  assert {
    condition     = aws_db_option_group.database[0].major_engine_version == "16.00" && toset([for o in aws_db_option_group.database[0].option : o.option_name]) == toset(["SQLSERVER_BACKUP_RESTORE", "TDE", "SSRS"])
    error_message = "An option group with native backup and restore, TDE and SSRS."
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_group.database)) == toset(["agent", "error"]) && aws_db_instance.database.manage_master_user_password
    error_message = "Agent and error logs exported; the password kept by RDS."
  }

  assert {
    condition     = aws_db_instance.database.domain_fqdn == "corp.example.com" && aws_db_instance.database.timezone == "Eastern Standard Time" && length(aws_iam_role.backup_restore) == 1
    error_message = "Joined to the self-managed domain, in its time zone, with a role for native backups."
  }
}

run "sqlserver_ssis_turns_on_the_clr" {
  command = plan

  variables {
    name                 = "etl"
    engine               = "sqlserver-ee"
    engine_version       = "15.00"
    options              = { SSIS = {} }
    domain               = "d-1234567890"
    domain_iam_role_name = "rds-directory-operations"
  }

  assert {
    condition     = contains([for p in aws_db_parameter_group.database[0].parameter : p.name if p.value == "1"], "clr enabled") && aws_db_parameter_group.database[0].family == "sqlserver-ee-15.0"
    error_message = "SSIS needs the CLR."
  }
}

run "sqlserver_express" {
  command = plan

  variables {
    name           = "lab"
    engine         = "sqlserver-ex"
    engine_version = "16.00.4185.3.v1"
    instance_class = "db.t3.small"
    storage        = 20
    max_storage    = 100
    multi_az       = false
  }

  assert {
    condition     = length(aws_db_option_group.database) == 0 && aws_db_parameter_group.database[0].family == "sqlserver-ex-16.0"
    error_message = "Express without options; a full version still gives the major version's family."
  }
}

run "rds_custom" {
  command = plan

  variables {
    name                        = "salesforce-sync"
    engine                      = "custom-sqlserver-se"
    engine_version              = "16.00.4185.3.v1"
    instance_class              = "db.m6i.xlarge"
    max_storage                 = null
    monitoring_role_arn         = null
    custom_iam_instance_profile = "AWSRDSCustom-operations-us-east-2"
  }

  assert {
    condition     = length(aws_db_parameter_group.database) == 0 && length(aws_db_option_group.database) == 0 && length(aws_cloudwatch_log_group.database) == 0
    error_message = "RDS Custom takes no parameter group, option group or log exports."
  }

  assert {
    condition     = !aws_db_instance.database.performance_insights_enabled && aws_db_instance.database.monitoring_interval == 0 && !aws_db_instance.database.auto_minor_version_upgrade && !aws_db_instance.database.iam_database_authentication_enabled
    error_message = "No Performance Insights, enhanced monitoring, automatic upgrades or IAM authentication on RDS Custom."
  }

  assert {
    condition     = aws_db_instance.database.custom_iam_instance_profile == "AWSRDSCustom-operations-us-east-2" && aws_db_instance.database.kms_key_id == var.kms_key_arn && aws_db_instance.database.backup_retention_period == 35 && aws_db_instance.database.multi_az
    error_message = "Its instance profile, the data key, 35 days of backups, Multi-AZ."
  }

  assert {
    condition     = aws_db_instance.database.manage_master_user_password == null && aws_secretsmanager_secret.password[0].name == "rds-custom/salesforce-sync/dbadmin" && aws_secretsmanager_secret.password[0].kms_key_id == var.kms_key_arn
    error_message = "The password goes write-only to a secret of its own, encrypted with the data key."
  }
}

run "rejects_express_multi_az" {
  command = plan

  variables {
    engine         = "sqlserver-ex"
    engine_version = "16.00"
    multi_az       = true
  }

  expect_failures = [var.multi_az]
}

run "rejects_old_web_multi_az" {
  command = plan

  variables {
    engine         = "sqlserver-web"
    engine_version = "15.00"
  }

  expect_failures = [var.multi_az]
}

run "rejects_options_on_web" {
  command = plan

  variables {
    engine         = "sqlserver-web"
    engine_version = "16.00"
    options        = { TDE = {} }
  }

  expect_failures = [var.options]
}

run "rejects_rds_custom_without_its_profile" {
  command = plan

  variables {
    engine              = "custom-sqlserver-ee"
    engine_version      = "16.00.4185.3.v1"
    max_storage         = null
    monitoring_role_arn = null
  }

  expect_failures = [var.custom_iam_instance_profile]
}

run "rejects_developer_edition_without_our_media" {
  command = plan

  variables {
    engine                      = "custom-sqlserver-dev"
    engine_version              = "16.00.4185.3.dbamp-v1"
    max_storage                 = null
    monitoring_role_arn         = null
    custom_iam_instance_profile = "AWSRDSCustom-operations-us-east-2"
  }

  expect_failures = [var.license_model]
}

run "rejects_a_half_set_domain" {
  command = plan

  variables {
    engine         = "sqlserver-se"
    engine_version = "16.00"
    domain_fqdn    = "corp.example.com"
  }

  expect_failures = [var.domain_dns_ips]
}
