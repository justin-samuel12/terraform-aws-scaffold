module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "placement" {
  source = "../../modules/placement"

  groups  = local.fixed
  network = local.network
  label   = "${var.environment}'s VPC in ${var.region}"
}

# Everything shared is found by name and tags: the VPC, subnets, security groups, roles, the data key, load balancers, listeners and zones.
data "aws_vpc" "vpc" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
    Name        = "vpc-01"
  }
}

# An Auto Scaling group's subnets: every zone of its tier.
data "aws_subnets" "tiers" {
  for_each = local.usable ? toset([for f in values(local.scaled) : try(f.tier, "private")]) : toset([])

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc[0].id]
  }

  tags = { Tier = each.key }
}

data "aws_subnet" "subnets" {
  for_each = local.usable ? toset([for s in values(local.servers) : s.subnet]) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Subnet = each.key }
}

data "aws_security_group" "groups" {
  for_each = local.usable ? toset(flatten([for f in values(local.files) : try(f.security_groups, [])])) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Name = each.key }
}

# Roles made in the iam stack, by name; an application on a blueprint has its own, made below, instead.
data "aws_iam_instance_profile" "profiles" {
  for_each = local.usable ? toset([for group, f in local.files : f.iam_instance_profile if !contains(keys(local.app_role_names), group)]) : toset([])

  name = each.key
}

# The account's shared policies a blueprint's role takes (session-manager, read-revisions), made by the iam stack.
data "aws_iam_policy" "shared" {
  for_each = local.usable ? local.app_role_policies : toset([])

  name = each.key
}

# One role and instance profile per application on a blueprint: the blueprint's permissions, the application's own identity.
module "app_roles" {
  source = "../../modules/iam-role"
  count  = local.usable && length(local.app_role_names) > 0 ? 1 : 0

  roles = {
    for group, name in local.app_role_names : name => {
      description      = "${group}'s servers in ${var.environment}, ${var.region} (blueprint ${local.blueprint_refs[group]})"
      services         = ["ec2"]
      managed_policies = try(tolist(local.blueprints[local.blueprint_refs[group]].role.managed_policies), [])
      policy_arns      = [for p in try(local.blueprints[local.blueprint_refs[group]].role.policies, []) : data.aws_iam_policy.shared[p].arn]
      statements = [for st in try(local.blueprints[local.blueprint_refs[group]].role.statement, []) : {
        effect    = try(st.effect, "Allow")
        actions   = tolist(st.actions)
        resources = [for r in tolist(st.resources) : replace(replace(replace(r, "{app}", group), "{environment}", var.environment), "{region}", var.region)]
        condition = [for c in try(st.condition, []) : { test = c.test, variable = c.variable, values = [for v in c.values : replace(replace(tostring(v), "{app}", group), "{environment}", var.environment)] }]
      }]
    }
  }
}

data "aws_kms_key" "data" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

data "aws_lb" "load_balancers" {
  for_each = local.usable ? toset(compact(concat([for r in local.routes : r.load_balancer], [for n in local.names : n.load_balancer]))) : toset([])

  name = "${var.environment}-${each.key}"
}

data "aws_lb_listener" "listeners" {
  for_each = local.usable ? toset(local.listener_keys) : toset([])

  load_balancer_arn = data.aws_lb.load_balancers[split(":", each.key)[0]].arn
  port              = tonumber(split(":", each.key)[1])
}

data "aws_lb_target_group" "targets" {
  for_each = local.usable ? toset(flatten([for t in values(local.targets) : keys(t)])) : toset([])

  tags = { Name = "${var.environment}-${replace(each.key, "/", "-")}", Environment = var.environment }
}

data "aws_route53_zone" "zones" {
  provider = aws.hub
  for_each = local.usable ? toset([for n in local.names : "${n.zone}|${n.private}"]) : toset([])

  name         = split("|", each.key)[0]
  private_zone = split("|", each.key)[1] == "true"
}

# One CodeDeploy service role per environment, only when some group's servers run an application deployed by CodeDeploy.
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
}

module "server_group" {
  source = "../../modules/server-group"

  providers = {
    aws     = aws
    aws.hub = aws.hub
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
    stickiness = try(each.value.target_group.stickiness.cookie_duration, null)
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
  autoscaling = can(each.value.autoscaling) ? {
    subnet_ids                    = data.aws_subnets.tiers[try(each.value.tier, "private")].ids
    min_size                      = each.value.autoscaling.min_size
    max_size                      = each.value.autoscaling.max_size
    desired_capacity              = each.value.autoscaling.desired_capacity
    target_tracking_configuration = try(each.value.autoscaling.target_tracking_configuration, null)
  } : null

  servers = {
    image_id           = each.value.ami
    security_group_ids = [for g in try(each.value.security_groups, []) : data.aws_security_group.groups[g].id]
    instance_profile   = contains(keys(local.app_role_names), each.key) ? module.app_roles[0].instance_profiles[local.app_role_names[each.key]] : data.aws_iam_instance_profile.profiles[each.value.iam_instance_profile].name
    kms_key_arn        = data.aws_kms_key.data[0].arn
    root_size          = try(each.value.root_block_device.volume_size, 30)
    backup             = try(each.value.backup, true)
    user_data          = contains(keys(local.user_data_paths), each.key) ? file(local.user_data_paths[each.key]) : null
    tags               = local.server_tags[each.key]
    volumes = {
      for name, v in try(each.value.ebs_block_device, {}) : name => {
        device     = v.device_name
        size       = v.volume_size
        iops       = try(v.iops, 3000)
        throughput = try(v.throughput, 125)
      }
    }
    members = {
      for name, s in local.servers : name => {
        subnet_id     = data.aws_subnet.subnets[s.subnet].id
        subnet        = s.subnet
        instance_type = s.type
        private_ip    = try(s.addresses.primary, null)
        secondary_ips = [for role, a in s.addresses : a if role != "primary"]
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
      zone_id     = data.aws_route53_zone.zones["${n.zone}|${n.private}"].zone_id
      name        = n.name
      lb_dns_name = data.aws_lb.load_balancers[n.load_balancer].dns_name
      lb_zone_id  = data.aws_lb.load_balancers[n.load_balancer].zone_id
    }
    if n.group == each.key
  ]
}

data "aws_caller_identity" "current" {}

# One per application the groups' CodeDeploy tags list: the same name in every environment, a deployment group per branch
# (or per environment when shared and containerized), finding its servers by their CodeDeploy:<application> tag.
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
