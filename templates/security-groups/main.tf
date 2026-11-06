module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "security_group" {
  source = "../../modules/security-group"

  vpc_id = data.aws_vpc.vpc.id
  groups = { for name, g in local.groups : name => g if length(local.problems) == 0 }
}
