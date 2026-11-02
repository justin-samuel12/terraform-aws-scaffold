# The VPC, the chosen tier's subnets, the security groups and the environment's data key, all found by name and tags.
data "aws_vpc" "vpc" {
  count = length(local.files) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
    Name        = "vpc-01"
  }
}

data "aws_subnets" "tiers" {
  for_each = local.tiers

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc[0].id]
  }

  tags = { Tier = each.key }
}

data "aws_security_group" "groups" {
  for_each = toset(flatten([for f in values(local.files) : try(f.security_groups, [])]))

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Name = each.key }
}

data "aws_kms_key" "data" {
  count = length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

module "efs_file_system" {
  source   = "../../modules/efs-file-system"
  for_each = local.files

  name               = "${var.environment}-${each.key}"
  kms_key_arn        = data.aws_kms_key.data[0].arn
  subnet_ids         = data.aws_subnets.tiers[try(each.value.tier, "data")].ids
  security_group_ids = [for g in try(each.value.security_groups, []) : data.aws_security_group.groups[g].id]
  access_points = {
    for name, a in try(each.value.access_points, {}) : name => {
      path        = a.root_directory.path
      uid         = a.posix_user.uid
      gid         = a.posix_user.gid
      permissions = try(tostring(a.root_directory.creation_info.permissions), "0750")
    }
  }
}
