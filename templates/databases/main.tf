# The VPC, its data tier, the security groups and the environment's data key, all found by name and tags.
data "aws_vpc" "vpc" {
  count = length(local.databases) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
    Name        = "vpc-01"
  }
}

data "aws_subnets" "data" {
  count = length(local.databases) > 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc[0].id]
  }

  tags = { Tier = "data" }
}

data "aws_security_group" "groups" {
  for_each = toset(flatten([for d in local.databases : try(d.security_groups, [])]))

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Name = each.key }
}

data "aws_kms_key" "data" {
  count = length(local.databases) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

module "monitoring_role" {
  source = "../../modules/iam-role"
  count  = length(local.databases) > 0 ? 1 : 0

  roles = {
    "rds-monitoring-${var.environment}" = {
      description      = "Enhanced monitoring for ${var.environment}'s databases"
      services         = ["monitoring.rds"]
      managed_policies = ["service-role/AmazonRDSEnhancedMonitoringRole"]
    }
  }
}

module "rds_instance" {
  source   = "../../modules/rds-instance"
  for_each = local.databases

  name                = "${var.environment}-${each.key}"
  engine              = each.value.engine
  engine_version      = tostring(each.value.engine_version)
  instance_class      = each.value.instance_class
  storage             = each.value.allocated_storage
  max_storage         = try(each.value.max_allocated_storage, each.value.allocated_storage * 5)
  multi_az            = try(each.value.multi_az, true)
  subnet_ids          = data.aws_subnets.data[0].ids
  security_group_ids  = [for g in try(each.value.security_groups, []) : data.aws_security_group.groups[g].id]
  kms_key_arn         = data.aws_kms_key.data[0].arn
  monitoring_role_arn = module.monitoring_role[0].arns["rds-monitoring-${var.environment}"]
}
