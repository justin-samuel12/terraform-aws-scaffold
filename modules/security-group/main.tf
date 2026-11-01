resource "aws_security_group" "groups" {
  for_each = var.groups

  name        = each.key
  description = each.value.description
  vpc_id      = var.vpc_id

  tags = { Name = each.key }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rules" {
  for_each = { for key, r in local.rules : key => r if r.direction == "ingress" }

  security_group_id            = aws_security_group.groups[each.value.owner].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr
  prefix_list_id               = each.value.prefix_list
  referenced_security_group_id = each.value.group == null ? null : aws_security_group.groups[each.value.group == "self" ? each.value.owner : each.value.group].id

  tags = { Name = "${each.value.owner}-in" }
}

resource "aws_vpc_security_group_egress_rule" "rules" {
  for_each = { for key, r in local.rules : key => r if r.direction == "egress" }

  security_group_id            = aws_security_group.groups[each.value.owner].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr
  prefix_list_id               = each.value.prefix_list
  referenced_security_group_id = each.value.group == null ? null : aws_security_group.groups[each.value.group == "self" ? each.value.owner : each.value.group].id

  tags = { Name = "${each.value.owner}-out" }
}
