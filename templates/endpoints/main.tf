module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

locals {
  resolved = {
    for name, e in local.endpoints : name => merge(e, {
      subnet_ids         = [for s in e.subnet_ids : startswith(s, "subnet-") ? s : data.aws_subnet.subnets[s].id]
      security_group_ids = [for g in e.security_group_ids : startswith(g, "sg-") ? g : data.aws_security_group.groups[g].id]
      route_table_ids    = [for s in e.route_table_ids : startswith(s, "rtb-") ? s : data.aws_route_table.route_tables[s].id]
    })
  }
}

module "vpc_endpoint" {
  source = "../../modules/vpc-endpoint"

  vpc_id    = data.aws_vpc.vpc.id
  endpoints = local.resolved
}
