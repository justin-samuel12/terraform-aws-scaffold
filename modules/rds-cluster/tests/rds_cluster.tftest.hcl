mock_provider "aws" {}

variables {
  name                   = "reporting"
  engine                 = "aurora-postgresql"
  engine_version         = "16.6"
  instance_class         = "db.r6g.large"
  subnet_ids             = ["subnet-data-1", "subnet-data-2", "subnet-data-3"]
  vpc_security_group_ids = ["sg-reporting-database"]
  instances              = 2
  kms_key_arn            = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  monitoring_role_arn    = "arn:aws:iam::111111111111:role/rds-monitoring-operations"
}

run "postgresql" {
  command = plan

  assert {
    condition     = aws_rds_cluster.cluster.manage_master_user_password && !aws_rds_cluster.cluster.skip_final_snapshot && aws_rds_cluster.cluster.backup_retention_period == 35 && aws_rds_cluster.cluster.deletion_protection
    error_message = "A managed, rotated password; a final snapshot; backups kept 35 days; protected from deletion."
  }

  assert {
    condition     = aws_rds_cluster.cluster.storage_encrypted && aws_rds_cluster.cluster.iam_database_authentication_enabled && aws_rds_cluster.cluster.tags.Backup == "standard"
    error_message = "Encrypted with the data key, IAM authentication on, in the backup plan."
  }

  assert {
    condition     = aws_rds_cluster_parameter_group.cluster.family == "aurora-postgresql16" && contains([for p in aws_rds_cluster_parameter_group.cluster.parameter : p.name], "rds.force_ssl")
    error_message = "The cluster's parameter group forces TLS."
  }

  assert {
    condition     = length(aws_rds_cluster_instance.instance) == 2 && aws_rds_cluster_instance.instance[1].identifier == "reporting-2" && aws_rds_cluster_instance.instance[0].performance_insights_enabled && aws_rds_cluster_instance.instance[0].monitoring_interval == 60
    error_message = "Two instances, each with Performance Insights and enhanced monitoring."
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_group.cluster)) == toset(["postgresql"]) && aws_cloudwatch_log_group.cluster["postgresql"].name == "/aws/rds/cluster/reporting/postgresql" && aws_cloudwatch_log_group.cluster["postgresql"].retention_in_days == 365
    error_message = "The PostgreSQL log, kept a year."
  }

  assert {
    condition     = output.port == 5432 && length(aws_rds_cluster.cluster.serverlessv2_scaling_configuration) == 0
    error_message = "PostgreSQL's port; provisioned, not serverless."
  }
}

run "mysql" {
  command = plan

  variables {
    engine         = "aurora-mysql"
    engine_version = "8.0.mysql_aurora.3.08.0"
    instances      = 3
  }

  assert {
    condition     = aws_rds_cluster_parameter_group.cluster.family == "aurora-mysql8.0" && contains([for p in aws_rds_cluster_parameter_group.cluster.parameter : p.name], "require_secure_transport")
    error_message = "Aurora MySQL 8.0's family, requiring TLS."
  }

  assert {
    condition     = length(aws_rds_cluster_instance.instance) == 3 && toset(keys(aws_cloudwatch_log_group.cluster)) == toset(["error", "slowquery"]) && output.port == 3306
    error_message = "Three instances; error and slow-query logs; MySQL's port."
  }
}

run "serverless" {
  command = plan

  variables {
    instance_class                     = "db.serverless"
    instances                          = 1
    serverlessv2_scaling_configuration = { min_capacity = 0.5, max_capacity = 8 }
  }

  assert {
    condition     = aws_rds_cluster.cluster.serverlessv2_scaling_configuration[0].max_capacity == 8 && aws_rds_cluster_instance.instance[0].instance_class == "db.serverless"
    error_message = "Serverless v2 scales each instance between its capacities."
  }
}

run "rejects_serverless_without_capacity" {
  command = plan

  variables {
    instance_class = "db.serverless"
  }

  expect_failures = [var.serverlessv2_scaling_configuration]
}

run "rejects_capacity_on_provisioned" {
  command = plan

  variables {
    serverlessv2_scaling_configuration = { min_capacity = 1, max_capacity = 4 }
  }

  expect_failures = [var.serverlessv2_scaling_configuration]
}

run "rejects_unknown_engine" {
  command = plan

  variables {
    engine = "aurora"
  }

  expect_failures = [var.engine]
}

run "pinned_versions_are_not_upgraded" {
  command = plan

  assert {
    condition     = alltrue([for i in aws_rds_cluster_instance.instance : !i.auto_minor_version_upgrade])
    error_message = "16.6 is pinned: no automatic minor upgrades, or the next plan would try to go back after AWS's."
  }
}
