module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "placement" {
  source = "../../modules/placement"

  groups  = local.files
  network = local.network
  label   = "${var.environment}'s VPC in ${var.region}"
}

# The VPC, the servers' subnets, security groups, instance profiles, target groups and the data key: all found by name and tags.
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
  for_each = local.usable ? toset(flatten([for f in values(local.files) : try(f.security_groups, [])])) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Name = each.key }
}

data "aws_iam_instance_profile" "profiles" {
  for_each = local.usable ? toset(compact([for f in values(local.files) : try(f.role, null)])) : toset([])

  name = each.key
}

data "aws_lb_target_group" "targets" {
  for_each = local.usable ? toset(flatten([for f in values(local.files) : keys(try(f.targets, {}))])) : toset([])

  tags = { Name = replace(each.key, "/", "-") }
}

data "aws_kms_key" "data" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

module "ec2_instance" {
  source   = "../../modules/ec2-instance"
  for_each = { for group, f in local.files : group => f if local.usable }

  environment        = var.environment
  group              = each.key
  image_id           = each.value.image
  security_group_ids = [for g in try(each.value.security_groups, []) : data.aws_security_group.groups[g].id]
  instance_profile   = data.aws_iam_instance_profile.profiles[each.value.role].name
  kms_key_arn        = data.aws_kms_key.data[0].arn
  root_size          = try(each.value.root_size, 30)
  protect            = try(each.value.protect, false)
  backup             = try(each.value.backup, true)
  user_data          = try(file("${local.config_dir}/${each.value.user_data}"), null)
  tags               = { for k, v in try(each.value.tags, {}) : k => tostring(v) }
  target_groups      = { for t, port in try(each.value.targets, {}) : t => { arn = data.aws_lb_target_group.targets[t].arn, port = port } }

  volumes = {
    for name, v in try(each.value.volumes, {}) : name => {
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
