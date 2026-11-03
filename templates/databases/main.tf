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

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

module "monitoring_role" {
  source = "../../modules/iam-role"
  count  = local.monitored ? 1 : 0

  roles = {
    "rds-monitoring-${var.environment}-${data.aws_region.current.region}" = {
      description      = "Enhanced monitoring for ${var.environment}'s databases"
      services         = ["monitoring.rds"]
      managed_policies = ["service-role/AmazonRDSEnhancedMonitoringRole"]
    }
  }
}

# RDS joins SQL Server to AWS Managed Microsoft AD with this role; a self-managed domain needs none.
module "directory_role" {
  source = "../../modules/iam-role"
  count  = local.managed_ad ? 1 : 0

  roles = {
    "rds-directory-${var.environment}-${data.aws_region.current.region}" = {
      description      = "Joins ${var.environment}'s SQL Server databases to AWS Managed Microsoft AD"
      services         = ["rds"]
      managed_policies = ["service-role/AmazonRDSDirectoryServiceAccess"]
    }
  }
}

# RDS Custom's servers run as this, one per environment and region; AWS insists the name start with AWSRDSCustom.
resource "aws_iam_role" "rds_custom" {
  count = local.any_custom ? 1 : 0

  name                 = local.instance_prefix
  description          = "RDS Custom for SQL Server servers in ${var.environment}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })

  tags = { Name = local.instance_prefix }
}

resource "aws_iam_role_policy_attachment" "rds_custom" {
  count = local.any_custom ? 1 : 0

  role       = aws_iam_role.rds_custom[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonRDSCustomInstanceProfileRolePolicy"
}

resource "aws_iam_role_policy" "rds_custom" {
  count = local.any_custom ? 1 : 0

  name = "${local.instance_prefix}-data-key"
  role = aws_iam_role.rds_custom[0].name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*", "kms:DescribeKey", "kms:CreateGrant"], Resource = data.aws_kms_key.data[0].arn }]
  })
}

resource "aws_iam_instance_profile" "rds_custom" {
  count = local.any_custom ? 1 : 0

  name = local.instance_prefix
  role = aws_iam_role.rds_custom[0].name

  tags = { Name = local.instance_prefix }

  depends_on = [aws_iam_role_policy_attachment.rds_custom, aws_iam_role_policy.rds_custom]
}

module "engine_version" {
  source   = "../../modules/rds-custom-engine-version"
  for_each = local.versions

  engine          = each.value.engine
  engine_version  = tostring(each.value.engine_version)
  source_image_id = each.value.source_image_id
  description     = each.value.description
}

module "rds_instance" {
  source   = "../../modules/rds-instance"
  for_each = local.instances

  password_generation = try(each.value.password_generation, 1)
  name                = "${var.environment}-${each.key}"
  engine              = each.value.engine
  engine_version      = each.value.kind == "rds-custom" && contains(keys(local.custom_versions), each.value.version) ? module.engine_version[local.custom_versions[each.value.version].file].engine_version : each.value.version
  instance_class      = each.value.instance_class
  storage             = each.value.allocated_storage
  max_storage         = each.value.kind == "rds-custom" ? null : try(each.value.max_allocated_storage, each.value.allocated_storage * 5)
  multi_az            = each.value.multi_az
  subnet_ids          = data.aws_subnets.data[0].ids
  security_group_ids  = [for g in try(each.value.security_groups, []) : data.aws_security_group.groups[g].id]
  kms_key_arn         = data.aws_kms_key.data[0].arn
  monitoring_role_arn = each.value.kind == "rds-custom" ? null : module.monitoring_role[0].arns["rds-monitoring-${var.environment}-${data.aws_region.current.region}"]

  license_model      = each.value.kind == "rds-custom" ? each.value.license : "license-included"
  timezone           = try(each.value.timezone, null)
  character_set_name = try(each.value.character_set_name, null)

  # Native backups go to a bucket of the buckets stack, named there <environment>-<file>-<account>-<region>.
  backup_restore_bucket = can(each.value.options.SQLSERVER_BACKUP_RESTORE) ? "${var.environment}-${each.value.options.SQLSERVER_BACKUP_RESTORE.bucket}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}" : null
  options = {
    for o, v in each.value.options : o => {
      port     = try(tonumber(v.port), local.sqlserver_options[o].port)
      settings = try({ for k, s in v : k => tostring(s) if k != "port" }, {})
    } if o != "SQLSERVER_BACKUP_RESTORE"
  }

  domain                 = try(each.value.domain, null)
  domain_iam_role_name   = can(each.value.domain) ? split("/", module.directory_role[0].arns["rds-directory-${var.environment}-${data.aws_region.current.region}"])[1] : null
  domain_fqdn            = try(each.value.domain_fqdn, null)
  domain_ou              = try(each.value.domain_ou, null)
  domain_auth_secret_arn = try(each.value.domain_auth_secret_arn, null)
  domain_dns_ips         = try(tolist(each.value.domain_dns_ips), null)

  custom_iam_instance_profile = each.value.kind == "rds-custom" ? aws_iam_instance_profile.rds_custom[0].name : null
}

module "rds_cluster" {
  source   = "../../modules/rds-cluster"
  for_each = local.clusters

  name                = "${var.environment}-${each.key}"
  engine              = each.value.engine
  engine_version      = each.value.version
  instance_class      = each.value.instance_class
  instances           = try(each.value.instances, 2)
  min_capacity        = try(each.value.serverlessv2_scaling_configuration.min_capacity, null)
  max_capacity        = try(each.value.serverlessv2_scaling_configuration.max_capacity, null)
  subnet_ids          = data.aws_subnets.data[0].ids
  security_group_ids  = [for g in try(each.value.security_groups, []) : data.aws_security_group.groups[g].id]
  kms_key_arn         = data.aws_kms_key.data[0].arn
  monitoring_role_arn = module.monitoring_role[0].arns["rds-monitoring-${var.environment}-${data.aws_region.current.region}"]
}
