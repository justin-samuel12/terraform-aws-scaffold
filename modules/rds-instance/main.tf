resource "aws_db_subnet_group" "database" {
  name       = var.name
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${local.name_prefix}${local.short_name}" })
}

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

  tags = merge(var.tags, { Name = "${local.name_prefix}${local.short_name}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_option_group" "database" {
  count = local.sqlserver && length(var.option) > 0 ? 1 : 0

  name_prefix              = "${var.name}-"
  option_group_description = "Options for ${var.name}"
  engine_name              = var.engine
  major_engine_version     = "${local.major}.00"

  dynamic "option" {
    for_each = var.option
    content {
      option_name                    = option.value.option_name
      port                           = option.value.port
      version                        = option.value.version
      vpc_security_group_memberships = option.value.vpc_security_group_memberships

      dynamic "option_settings" {
        for_each = option.value.option_settings
        content {
          name  = option_settings.value.name
          value = option_settings.value.value
        }
      }
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${local.short_name}" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "database" {
  for_each = toset(local.log_exports)

  name              = "/aws/rds/instance/${var.name}/${each.key}"
  retention_in_days = 365

  tags = merge(var.tags, { Name = "${local.name_prefix}${local.short_name}" })
}

resource "aws_secretsmanager_secret" "password" {
  count = local.custom ? 1 : 0

  name        = "rds-custom/${var.name}/dbadmin"
  description = "The dbadmin login for ${var.name}"
  kms_key_id  = var.kms_key_arn

  tags = merge(var.tags, { Name = "${local.name_prefix}${local.short_name}" })
}

resource "aws_secretsmanager_secret_version" "password" {
  count = local.custom ? 1 : 0

  secret_id                = aws_secretsmanager_secret.password[0].id
  secret_string_wo         = jsonencode({ username = "dbadmin", password = local.password })
  secret_string_wo_version = var.password_wo_version

  depends_on = [aws_db_instance.database]

  lifecycle {
    replace_triggered_by = [aws_db_instance.database]
  }
}

resource "aws_db_instance" "database" {
  identifier     = var.name
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class
  license_model  = var.license_model
  port           = local.sqlserver || local.custom ? 1433 : null

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  username                      = "dbadmin"
  manage_master_user_password   = local.custom ? null : true
  master_user_secret_kms_key_id = local.custom ? null : var.kms_key_arn
  password_wo                   = local.custom ? local.password : null
  password_wo_version           = local.custom ? var.password_wo_version : null

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = var.vpc_security_group_ids
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

  iam_database_authentication_enabled = !(local.sqlserver || local.custom)
  enabled_cloudwatch_logs_exports     = local.log_exports

  backup_retention_period   = 35
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  deletion_protection       = !local.custom
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"

  auto_minor_version_upgrade  = !local.custom && !local.pinned
  allow_major_version_upgrade = false

  performance_insights_enabled          = !local.custom
  performance_insights_kms_key_id       = local.custom ? null : var.kms_key_arn
  performance_insights_retention_period = local.custom ? null : 7
  monitoring_interval                   = local.custom ? 0 : 60
  monitoring_role_arn                   = var.monitoring_role_arn

  tags = merge(var.tags, { Name = "${local.name_prefix}${local.short_name}", Backup = "standard" })

  depends_on = [aws_cloudwatch_log_group.database, aws_secretsmanager_secret.password]

  timeouts {
    create = "4h"
    update = "4h"
    delete = "4h"
  }

  lifecycle {
    prevent_destroy = true
  }
}
