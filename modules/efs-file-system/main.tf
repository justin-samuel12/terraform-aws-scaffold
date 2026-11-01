data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_efs_file_system" "file_system" {
  creation_token  = var.name
  encrypted       = true
  kms_key_id      = var.kms_key_arn
  throughput_mode = "elastic"

  # Files unused for 30 days move to cheaper storage, and come back the first time they are read.
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = { Name = var.name, Backup = "standard" }

  lifecycle {
    prevent_destroy = true
  }
}

# The environment's backup plan takes these backups; EFS's own automatic ones would only duplicate them.
resource "aws_efs_backup_policy" "file_system" {
  file_system_id = aws_efs_file_system.file_system.id

  backup_policy {
    status = "DISABLED"
  }
}

resource "aws_efs_mount_target" "zones" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.file_system.id
  subnet_id       = each.key
  security_groups = var.security_group_ids
}

# Only encrypted connections, and only through this file system's own mount targets, from this account.
resource "aws_efs_file_system_policy" "file_system" {
  file_system_id = aws_efs_file_system.file_system.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "*"
        Resource  = aws_efs_file_system.file_system.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "MountThroughMountTargets"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
        Resource  = aws_efs_file_system.file_system.arn
        Condition = { Bool = { "elasticfilesystem:AccessedViaMountTarget" = "true" } }
      },
    ]
  })
}

resource "aws_efs_access_point" "access_points" {
  for_each = var.access_points

  file_system_id = aws_efs_file_system.file_system.id

  posix_user {
    uid = each.value.uid
    gid = each.value.gid
  }

  root_directory {
    path = each.value.path
    creation_info {
      owner_uid   = each.value.uid
      owner_gid   = each.value.gid
      permissions = each.value.permissions
    }
  }

  tags = { Name = "${var.name}-${each.key}" }
}
