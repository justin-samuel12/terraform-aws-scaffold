locals {
  resolved = {
    for name, fs in local.file_systems : name => merge(fs, {
      mount_targets = {
        for m in fs.mount_targets : m.subnet_id => {
          subnet_id       = startswith(m.subnet_id, "subnet-") ? m.subnet_id : data.aws_subnet.subnets[m.subnet_id].id
          security_groups = [for g in m.security_groups : startswith(g, "sg-") ? g : data.aws_security_group.groups[g].id]
        }
      }
    }) if local.usable
  }
}

module "efs_file_system" {
  source   = "../../modules/efs-file-system"
  for_each = local.resolved

  name          = "${var.environment}-${each.key}"
  kms_key_arn   = data.aws_kms_key.data[0].arn
  tags          = each.value.tags
  mount_targets = each.value.mount_targets
  access_points = each.value.access_points
}
