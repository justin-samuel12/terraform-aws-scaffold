resource "aws_db_subnet_group" "cluster" {
  name       = var.name
  subnet_ids = var.subnet_ids

  tags = { Name = var.name }
}

resource "aws_rds_cluster_parameter_group" "cluster" {
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

# The instances' own group: empty for now, so a setting can be changed later without replacing anything.
resource "aws_db_parameter_group" "instance" {
  name_prefix = "${var.name}-instance-"
  family      = local.family

  tags = { Name = var.name }

  lifecycle {
    create_before_destroy = true
  }
}

# Created before the cluster, so its logs are kept a year rather than forever.
resource "aws_cloudwatch_log_group" "cluster" {
  for_each = toset(local.log_exports)

  name              = "/aws/rds/cluster/${var.name}/${each.key}"
  retention_in_days = 365

  tags = { Name = var.name }
}

resource "aws_rds_cluster" "cluster" {
  cluster_identifier = var.name
  engine             = var.engine
  engine_version     = var.engine_version
  port               = local.port

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # RDS keeps the password in Secrets Manager and rotates it; it never passes through Terraform.
  master_username               = "dbadmin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.cluster.name
  vpc_security_group_ids          = var.security_group_ids
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.cluster.name

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = local.log_exports

  backup_retention_period      = 35
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${var.name}-final"
  allow_major_version_upgrade  = false

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.instance_class == "db.serverless" ? [1] : []
    content {
      min_capacity = var.min_capacity
      max_capacity = var.max_capacity
    }
  }

  tags = { Name = var.name, Backup = "standard" }

  depends_on = [aws_cloudwatch_log_group.cluster]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_rds_cluster_instance" "instance" {
  count = var.instances

  identifier              = "${var.name}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.cluster.id
  engine                  = aws_rds_cluster.cluster.engine
  engine_version          = aws_rds_cluster.cluster.engine_version
  instance_class          = var.instance_class
  db_subnet_group_name    = aws_db_subnet_group.cluster.name
  db_parameter_group_name = aws_db_parameter_group.instance.name
  publicly_accessible     = false
  ca_cert_identifier      = "rds-ca-rsa2048-g1"
  promotion_tier          = count.index

  auto_minor_version_upgrade            = true
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = var.monitoring_role_arn

  copy_tags_to_snapshot = true

  tags = { Name = "${var.name}-${count.index + 1}" }
}
