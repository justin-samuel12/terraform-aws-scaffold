data "aws_partition" "current" {}

resource "aws_db_subnet_group" "database" {
  name       = var.name
  subnet_ids = var.subnet_ids

  tags = { Name = var.name }
}

# RDS Custom takes no parameter or option groups: its settings live on the server.
resource "aws_db_parameter_group" "database" {
  count = local.custom ? 0 : 1

  name_prefix = "${var.name}-"
  family      = local.family

  dynamic "parameter" {
    for_each = local.parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }

  tags = { Name = var.name }

  lifecycle {
    create_before_destroy = true
  }
}

# Native backup and restore: SQL Server writes .bak files to the bucket, encrypted with the data key.
resource "aws_iam_role" "backup_restore" {
  count = var.backup_restore_bucket == null ? 0 : 1

  name                 = "${var.name}-backup-restore"
  description          = "Native backup and restore for ${var.name}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "rds.amazonaws.com" } }]
  })

  tags = { Name = "${var.name}-backup-restore" }
}

resource "aws_iam_role_policy" "backup_restore" {
  count = var.backup_restore_bucket == null ? 0 : 1

  name = "${var.name}-backup-restore-policy"
  role = aws_iam_role.backup_restore[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.backup_restore_bucket}" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:ListMultipartUploadParts", "s3:AbortMultipartUpload"], Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.backup_restore_bucket}/*" },
      { Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"], Resource = var.kms_key_arn },
    ]
  })
}

resource "aws_db_option_group" "database" {
  count = local.sqlserver && length(local.options) > 0 ? 1 : 0

  name_prefix              = "${var.name}-"
  option_group_description = "Options for ${var.name}"
  engine_name              = var.engine
  major_engine_version     = "${local.major}.00"

  dynamic "option" {
    for_each = local.options
    content {
      option_name                    = option.key
      port                           = option.value.port
      vpc_security_group_memberships = option.value.security_groups

      dynamic "option_settings" {
        for_each = option.value.settings
        content {
          name  = option_settings.key
          value = option_settings.value
        }
      }
    }
  }

  tags = { Name = var.name }

  depends_on = [aws_iam_role_policy.backup_restore]

  lifecycle {
    create_before_destroy = true
  }
}

# Created before the database, so its logs are kept a year rather than forever.
resource "aws_cloudwatch_log_group" "database" {
  for_each = toset(local.log_exports)

  name              = "/aws/rds/instance/${var.name}/${each.key}"
  retention_in_days = 365

  tags = { Name = var.name }
}

# RDS Custom cannot keep its own password in Secrets Manager: one is made at creation and handed over write-only, never in state or plan.
resource "aws_secretsmanager_secret" "password" {
  count = local.custom ? 1 : 0

  name        = "rds-custom/${var.name}/dbadmin"
  description = "The dbadmin login for ${var.name}"
  kms_key_id  = var.kms_key_arn

  tags = { Name = var.name }
}

resource "aws_secretsmanager_secret_version" "password" {
  count = local.custom ? 1 : 0

  secret_id                = aws_secretsmanager_secret.password[0].id
  secret_string_wo         = jsonencode({ username = "dbadmin", password = local.password })
  secret_string_wo_version = 1
}

resource "aws_db_instance" "database" {
  identifier     = var.name
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class
  license_model  = local.sqlserver || local.custom ? var.license_model : null
  port           = local.sqlserver || local.custom ? 1433 : null

  allocated_storage     = var.storage
  max_allocated_storage = var.max_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  # RDS keeps the password in Secrets Manager and rotates it; it never passes through Terraform.
  username                      = "dbadmin"
  manage_master_user_password   = local.custom ? null : true
  master_user_secret_kms_key_id = local.custom ? null : var.kms_key_arn
  password_wo                   = local.custom ? local.password : null
  password_wo_version           = local.custom ? 1 : null

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false
  parameter_group_name   = local.custom ? null : aws_db_parameter_group.database[0].name
  option_group_name      = try(aws_db_option_group.database[0].name, null)
  ca_cert_identifier     = local.custom ? null : "rds-ca-rsa2048-g1"

  timezone           = var.timezone
  character_set_name = var.character_set_name

  domain                 = var.domain
  domain_iam_role_name   = var.domain_iam_role_name
  domain_fqdn            = var.domain_fqdn
  domain_ou              = var.domain_ou
  domain_auth_secret_arn = var.domain_auth_secret_arn
  domain_dns_ips         = var.domain_dns_ips

  custom_iam_instance_profile = var.custom_iam_instance_profile

  # SQL Server has no IAM database authentication.
  iam_database_authentication_enabled = !(local.sqlserver || local.custom)
  enabled_cloudwatch_logs_exports     = local.log_exports

  backup_retention_period   = 35
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  deletion_protection       = !local.custom
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"

  # RDS Custom upgrades only when we choose a new version for it.
  auto_minor_version_upgrade  = !local.custom
  allow_major_version_upgrade = false

  performance_insights_enabled          = !local.custom
  performance_insights_kms_key_id       = local.custom ? null : var.kms_key_arn
  performance_insights_retention_period = local.custom ? null : 7
  monitoring_interval                   = local.custom ? 0 : 60
  monitoring_role_arn                   = var.monitoring_role_arn

  tags = { Name = var.name, Backup = "standard" }

  depends_on = [aws_cloudwatch_log_group.database, aws_secretsmanager_secret_version.password]

  # RDS Custom builds its server for hours, and Multi-AZ SQL Server takes a while too.
  timeouts {
    create = "4h"
    update = "4h"
    delete = "4h"
  }

  lifecycle {
    prevent_destroy = true
  }
}
