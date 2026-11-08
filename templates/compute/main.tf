module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "blueprint" {
  source = "../../modules/blueprint"

  files       = local.raw_files
  dir         = local.blueprints_dir
  label       = "blueprints/compute"
  body        = "group"
  example     = "backend-service/v1"
  choices     = { instance_type = "instance_types" }
  sections    = ["role"]
  environment = var.environment
  region      = var.region
}

check "blueprint_versions" {
  assert {
    condition     = length(module.blueprint.warnings) == 0
    error_message = join("; ", module.blueprint.warnings)
  }
}

module "placement" {
  source = "../../modules/placement"

  groups   = local.fixed
  network  = local.network
  label    = "${var.environment}'s VPC in ${var.region}"
  existing = local.existing
}

module "app_roles" {
  source = "../../modules/iam-role"
  count  = local.usable && length(local.app_role_names) > 0 ? 1 : 0

  roles = {
    for group, name in local.app_role_names : name => {
      description = "${group}'s servers in ${var.environment}, ${var.region} (blueprint ${local.blueprint_refs[group]})"
      services    = ["ec2"]
      policy_arns = [for p in try(tolist(local.blueprints[local.blueprint_refs[group]].role.managed_policy_arns), []) : startswith(p, "arn:") ? p : data.aws_iam_policy.shared[p].arn]
      statements = [for st in try(local.blueprints[local.blueprint_refs[group]].role.statement, []) : {
        effect    = st.effect
        actions   = tolist(st.actions)
        resources = [for r in tolist(st.resources) : replace(replace(replace(r, "{app}", group), "{environment}", var.environment), "{region}", var.region)]
        condition = [for c in try(st.condition, []) : { test = c.test, variable = c.variable, values = [for v in c.values : replace(replace(tostring(v), "{app}", group), "{environment}", var.environment)] }]
      }]
    }
  }

  role_boundary = module.role_boundary.role_boundary
}

module "codedeploy_role" {
  source = "../../modules/iam-role"
  count  = local.usable && length(local.applications) > 0 ? 1 : 0

  roles = {
    "codedeploy-${var.environment}-${var.region}" = {
      description      = "CodeDeploy deploying ${var.environment}'s servers"
      services         = ["codedeploy"]
      managed_policies = ["service-role/AWSCodeDeployRole"]
    }
  }

  role_boundary = module.role_boundary.role_boundary
}

module "server_group" {
  source = "../../modules/server-group"

  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  for_each = { for group, f in local.files : group => f if local.usable }

  name        = each.key
  environment = var.environment
  vpc_id      = data.aws_vpc.vpc[0].id
  port        = try(each.value.target_group.port, null)
  health      = try(each.value.target_group.health_check.path, "/")
  target = {
    protocol   = try(each.value.target_group.protocol, "HTTP")
    matcher    = try(tostring(each.value.target_group.health_check.matcher), "200-399")
    stickiness = try(each.value.target_group.stickiness, null)
    slow_start = try(each.value.target_group.slow_start, 0)
  }
  targets = {
    for t, port in local.targets[each.key] : t => {
      arn  = data.aws_lb_target_group.targets[t].arn
      name = data.aws_lb_target_group.targets[t].name
      port = port
    }
  }
  instance_type = try(each.value.instance_type, null)
  autoscaling = can(each.value.autoscaling_group) ? {
    subnet_ids       = data.aws_subnets.tiers[try(each.value.tier, "private")].ids
    min_size         = each.value.autoscaling_group.min_size
    max_size         = each.value.autoscaling_group.max_size
    desired_capacity = each.value.autoscaling_group.desired_capacity
    target_tracking_configuration = can(each.value.autoscaling_policy.target_tracking_configuration) ? {
      predefined_metric_type = each.value.autoscaling_policy.target_tracking_configuration.predefined_metric_specification.predefined_metric_type
      resource_label         = try(each.value.autoscaling_policy.target_tracking_configuration.predefined_metric_specification.resource_label, null)
      target_value           = each.value.autoscaling_policy.target_tracking_configuration.target_value
    } : null
  } : null

  servers = {
    image_id           = startswith(each.value.ami, "ami-") ? each.value.ami : data.aws_ami.images[each.value.ami].id
    security_group_ids = [for g in try(each.value.vpc_security_group_ids, []) : startswith(g, "sg-") ? g : data.aws_security_group.groups[g].id]
    instance_profile   = contains(keys(local.app_role_names), each.key) ? module.app_roles[0].instance_profiles[local.app_role_names[each.key]] : data.aws_iam_instance_profile.profiles[each.value.iam_instance_profile].name
    kms_key_arn        = data.aws_kms_key.data[0].arn
    root_size          = try(each.value.root_block_device.volume_size, 30)
    user_data          = contains(keys(local.user_data_paths), each.key) ? file(local.user_data_paths[each.key]) : null
    tags               = local.group_tags[each.key]
    volumes = {
      for v in try(tolist(each.value.ebs_block_device), []) : basename(v.device_name) => {
        device     = v.device_name
        size       = v.volume_size
        name       = try(tostring(v.tags.Name), basename(v.device_name))
        iops       = try(v.iops, 3000)
        throughput = try(v.throughput, 125)
        tags       = try(tomap(v.tags), {})
      }
    }
    members = {
      for name, s in local.servers : name => {
        subnet_id     = data.aws_subnet.subnets[s.subnet].id
        subnet        = s.subnet
        instance_type = s.type
        private_ip    = s.private_ip
        secondary_ips = s.secondary_ips
        tags          = local.member_tags[name]
      }
      if s.group == each.key
    }
  }

  routes = [
    for r in local.routes : {
      listener_arn = data.aws_lb_listener.listeners["${r.load_balancer}:${r.listener}"].arn
      hosts        = r.hosts
      paths        = r.paths
      priority     = r.priority
    }
    if r.group == each.key
  ]

  names = [
    for n in local.names : {
      zone_id                = n.by_id ? n.zone : data.aws_route53_zone.zones["${n.zone}|${n.private}"].zone_id
      name                   = n.name
      type                   = n.type
      lb_dns_name            = data.aws_lb.load_balancers[n.load_balancer].dns_name
      lb_zone_id             = data.aws_lb.load_balancers[n.load_balancer].zone_id
      evaluate_target_health = n.evaluate
    }
    if n.group == each.key && !n.own
  ]
  own_names = [
    for n in local.names : {
      zone_id                = data.aws_route53_zone.own_zones["${n.zone}|${n.private}"].zone_id
      name                   = n.name
      type                   = n.type
      lb_dns_name            = data.aws_lb.load_balancers[n.load_balancer].dns_name
      lb_zone_id             = data.aws_lb.load_balancers[n.load_balancer].zone_id
      evaluate_target_health = n.evaluate
    }
    if n.group == each.key && n.own
  ]
}

resource "aws_route53_record" "servers" {
  for_each = local.usable ? local.server_names : {}

  zone_id = data.aws_route53_zone.own_zones["${local.own_zone}|true"].zone_id
  name    = each.value
  type    = "A"
  ttl     = 300
  records = [module.server_group[local.servers[each.key].group].servers[each.key].private_ip]
}

module "codedeploy_application" {
  source   = "../../modules/codedeploy-application"
  for_each = local.usable ? local.applications : toset([])

  name                         = each.key
  environment                  = var.environment
  region                       = var.region
  account_id                   = data.aws_caller_identity.current.account_id
  containerized                = local.containerized[each.key]
  groups                       = local.deployment[each.key].groups
  deployment_config_name       = local.deployment[each.key].config_name
  rollback_events              = local.deployment[each.key].rollback_events
  selector                     = try(local.application_selectors[each.key][0], null)
  autoscaling_groups           = compact([for g in local.application_groups[each.key] : module.server_group[g].autoscaling_group])
  target_group_names           = distinct(flatten([for g in local.application_groups[each.key] : module.server_group[g].target_group_names]))
  servers_behind_load_balancer = sum(concat([0], [for g in local.application_groups[each.key] : module.server_group[g].size if length(module.server_group[g].target_group_names) > 0]))
  service_role_arn             = module.codedeploy_role[0].arns["codedeploy-${var.environment}-${var.region}"]
  bootstrap                    = module.ip_plan.codedeploy.bootstrap
}

module "role_boundary" {
  source = "../../modules/role-boundary"

  duties_file = "${path.module}/../duties.yml"
}
