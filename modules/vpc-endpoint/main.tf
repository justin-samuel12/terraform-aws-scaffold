resource "aws_vpc_endpoint" "endpoints" {
  for_each = var.endpoints

  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = each.value.vpc_endpoint_type
  subnet_ids          = each.value.vpc_endpoint_type == "Interface" ? each.value.subnet_ids : null
  security_group_ids  = each.value.vpc_endpoint_type == "Interface" ? each.value.security_group_ids : null
  private_dns_enabled = each.value.private_dns_enabled
  route_table_ids     = each.value.vpc_endpoint_type == "Gateway" ? each.value.route_table_ids : null

  tags = merge(each.value.tags, { Name = "${local.name_prefix}${each.key}" })
}
