resource "aws_efs_file_system" "file_system" {
  creation_token  = var.name
  encrypted       = true
  kms_key_id      = var.kms_key_arn
  throughput_mode = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${local.short_name}" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_efs_backup_policy" "file_system" {
  file_system_id = aws_efs_file_system.file_system.id

  backup_policy {
    status = "DISABLED"
  }
}

resource "aws_efs_mount_target" "zones" {
  for_each = var.mount_targets

  file_system_id  = aws_efs_file_system.file_system.id
  subnet_id       = each.value.subnet_id
  security_groups = each.value.security_groups
}

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
    uid            = each.value.posix_user.uid
    gid            = each.value.posix_user.gid
    secondary_gids = each.value.posix_user.secondary_gids
  }

  root_directory {
    path = each.value.root_directory.path

    dynamic "creation_info" {
      for_each = each.value.root_directory.creation_info == null ? [] : [each.value.root_directory.creation_info]
      content {
        owner_uid   = creation_info.value.owner_uid
        owner_gid   = creation_info.value.owner_gid
        permissions = creation_info.value.permissions
      }
    }
  }

  tags = merge(each.value.tags, { Name = "${local.name_prefix}${local.short_name}-${each.key}" })
}
