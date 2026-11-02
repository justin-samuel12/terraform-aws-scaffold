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
    condition     = aws_db_parameter_group.database.family == "mysql8.0" && contains([for p in aws_db_parameter_group.database.parameter : p.name if p.value == "1"], "require_secure_transport")
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
    condition     = aws_db_parameter_group.database.family == "postgres16" && contains([for p in aws_db_parameter_group.database.parameter : p.name], "rds.force_ssl")
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
