module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

resource "aws_route53_zone" "private" {
  count = local.names.private == null ? 0 : 1

  name    = local.names.private
  comment = "${var.environment}'s private names: servers, databases, internal load balancers"

  vpc {
    vpc_id     = data.aws_vpc.vpcs[local.regions[0]].id
    vpc_region = local.regions[0]
  }

  tags = { Name = "${title(var.environment)} - ${local.names.private}" }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [vpc]
  }
}
