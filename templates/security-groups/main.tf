module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

# The environment's VPC is found by its tags, not by reading the network stack's state.
data "aws_vpc" "vpc" {
  tags = {
    Environment = var.environment
    Component   = "network"
    Name        = "vpc-01"
  }
}

# Prefix lists are built in the region's hub from config/global.yml, and found here by name.
data "aws_ec2_managed_prefix_list" "lists" {
  for_each = local.list_names

  name = each.key
}

# Another environment's group, found by its tags, when the region's hub lets VPCs reference each other's groups.
data "aws_security_group" "remote" {
  for_each = local.remote_names

  tags = {
    Environment = split("/", each.key)[0]
    Name        = split("/", each.key)[1]
  }
}

module "security_group" {
  source = "../../modules/security-group"

  vpc_id        = data.aws_vpc.vpc.id
  internal_cidr = module.ip_plan.internal_cidr
  groups        = { for name, g in local.groups : name => g if length(local.problems) == 0 }
}
