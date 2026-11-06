module "blueprint" {
  source = "../../modules/blueprint"

  files       = local.raw_files
  dir         = local.blueprints_dir
  label       = "blueprints/databases"
  body        = "database"
  example     = "sqlserver/v1"
  choices     = { instance_class = "instance_classes" }
  environment = var.environment
  region      = data.aws_region.current.region
}

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

module "rds_instance" {
  source   = "../../modules/rds-instance"
  for_each = local.instances

  tags = { for k, v in try(local.files[each.key].tags, {}) : k => tostring(v) }

  name                   = "${var.environment}-${each.key}"
  engine                 = each.value.engine
  engine_version         = each.value.kind == "rds-custom" && contains(keys(local.custom_versions), tostring(each.value.engine_version)) ? module.engine_version[local.custom_versions[tostring(each.value.engine_version)].file].engine_version : tostring(each.value.engine_version)
  instance_class         = each.value.instance_class
  allocated_storage      = each.value.allocated_storage
  max_allocated_storage  = try(each.value.max_allocated_storage, null)
  multi_az               = try(tobool(each.value.multi_az), null)
  license_model          = try(tostring(each.value.license_model), null)
  subnet_ids             = data.aws_subnets.data[0].ids
  vpc_security_group_ids = [for g in try(each.value.vpc_security_group_ids, []) : lookup(local.group_id, tostring(g), tostring(g))]
  kms_key_arn            = data.aws_kms_key.data[0].arn
  monitoring_role_arn    = each.value.kind == "rds-custom" ? null : module.monitoring_role[0].arns["rds-monitoring-${var.environment}-${data.aws_region.current.region}"]

  timezone           = try(each.value.timezone, null)
  character_set_name = try(each.value.character_set_name, null)
  option             = local.option_args[each.key]

  domain                 = try(each.value.domain, null)
  domain_iam_role_name   = try(each.value.domain_iam_role_name, null)
  domain_fqdn            = try(each.value.domain_fqdn, null)
  domain_ou              = try(each.value.domain_ou, null)
  domain_auth_secret_arn = try(each.value.domain_auth_secret_arn, null)
  domain_dns_ips         = try([for ip in each.value.domain_dns_ips : tostring(ip)], null)

  password_wo_version         = try(tonumber(each.value.password_wo_version), null)
  custom_iam_instance_profile = each.value.kind == "rds-custom" ? aws_iam_instance_profile.rds_custom[0].name : null
}

module "rds_cluster" {
  source   = "../../modules/rds-cluster"
  for_each = local.clusters

  tags = { for k, v in try(local.files[each.key].tags, {}) : k => tostring(v) }

  name                               = "${var.environment}-${each.key}"
  engine                             = each.value.engine
  engine_version                     = tostring(each.value.engine_version)
  instance_class                     = each.value.instance_class
  instances                          = each.value.count
  serverlessv2_scaling_configuration = try({ min_capacity = tonumber(each.value.serverlessv2_scaling_configuration.min_capacity), max_capacity = tonumber(each.value.serverlessv2_scaling_configuration.max_capacity) }, null)
  subnet_ids                         = data.aws_subnets.data[0].ids
  vpc_security_group_ids             = [for g in try(each.value.vpc_security_group_ids, []) : lookup(local.group_id, tostring(g), tostring(g))]
  kms_key_arn                        = data.aws_kms_key.data[0].arn
  monitoring_role_arn                = module.monitoring_role[0].arns["rds-monitoring-${var.environment}-${data.aws_region.current.region}"]
}
