module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "placement" {
  source = "../../modules/placement"

  groups  = { for app, f in local.files : app => try(f.servers, {}) }
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

data "aws_subnet" "subnets" {
  for_each = local.usable ? toset([for s in values(local.servers) : s.subnet]) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Subnet = each.key }
}

data "aws_security_group" "groups" {
  for_each = local.usable ? toset(flatten([for f in values(local.files) : try(f.servers.security_groups, [])])) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Name = each.key }
}

data "aws_iam_instance_profile" "profiles" {
  for_each = local.usable ? toset([for f in values(local.files) : f.servers.role]) : toset([])

  name = each.key
}

data "aws_kms_key" "data" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

data "aws_lb" "load_balancers" {
  for_each = local.usable ? toset(compact(concat([for r in local.routes : r.load_balancer], [for n in local.names : n.load_balancer]))) : toset([])

  name = each.key
}

data "aws_lb_listener" "listeners" {
  for_each = local.usable ? toset(local.listener_keys) : toset([])

  load_balancer_arn = data.aws_lb.load_balancers[split(":", each.key)[0]].arn
  port              = tonumber(split(":", each.key)[1])
}

data "aws_lb_target_group" "targets" {
  for_each = local.usable ? toset(flatten([for t in values(local.targets) : keys(t)])) : toset([])

  tags = { Name = replace(each.key, "/", "-") }
}

data "aws_route53_zone" "zones" {
  for_each = local.usable ? toset([for n in local.names : "${n.zone}|${n.private}"]) : toset([])

  name         = split("|", each.key)[0]
  private_zone = split("|", each.key)[1] == "true"
}

# One CodeDeploy service role per environment, only when some application is deployed by CodeDeploy.
module "codedeploy_role" {
  source = "../../modules/iam-role"
  count  = local.usable && anytrue([for f in values(local.files) : can(f.deploy)]) ? 1 : 0

  roles = {
    "codedeploy-${var.environment}" = {
      description      = "CodeDeploy deploying ${var.environment}'s applications"
      services         = ["codedeploy"]
      managed_policies = ["service-role/AWSCodeDeployRole"]
    }
  }
}

module "application" {
  source   = "../../modules/application"
  for_each = { for app, f in local.files : app => f if local.usable }

  name        = each.key
  environment = var.environment
  vpc_id      = data.aws_vpc.vpc[0].id
  port        = try(each.value.port, null)
  health      = try(each.value.health, "/")
  target = {
    protocol   = try(each.value.target.protocol, "HTTP")
    matcher    = try(tostring(each.value.target.matcher), "200-399")
    stickiness = try(each.value.target.stickiness, null)
    slow_start = try(each.value.target.slow_start, 0)
  }
  targets = {
    for t, port in local.targets[each.key] : t => {
      arn  = data.aws_lb_target_group.targets[t].arn
      name = data.aws_lb_target_group.targets[t].name
      port = port
    }
  }
  deploy              = try(each.value.deploy, null)
  codedeploy_role_arn = try(module.codedeploy_role[0].arns["codedeploy-${var.environment}"], null)

  servers = {
    image_id           = each.value.servers.image
    security_group_ids = [for g in try(each.value.servers.security_groups, []) : data.aws_security_group.groups[g].id]
    instance_profile   = data.aws_iam_instance_profile.profiles[each.value.servers.role].name
    kms_key_arn        = data.aws_kms_key.data[0].arn
    root_size          = try(each.value.servers.root_size, 30)
    backup             = try(each.value.servers.backup, true)
    user_data          = try(file("${local.config_dir}/${each.value.servers.user_data}"), null)
    tags               = { for k, v in try(each.value.servers.tags, {}) : k => tostring(v) }
    volumes = {
      for name, v in try(each.value.servers.volumes, {}) : name => {
        device     = v.device
        size       = v.size
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
    if r.app == each.key
  ]

  names = [
    for n in local.names : {
      zone_id     = data.aws_route53_zone.zones["${n.zone}|${n.private}"].zone_id
      name        = n.name
      lb_dns_name = data.aws_lb.load_balancers[n.load_balancer].dns_name
      lb_zone_id  = data.aws_lb.load_balancers[n.load_balancer].zone_id
    }
    if n.app == each.key
  ]
}
