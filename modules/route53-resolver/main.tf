resource "aws_security_group" "resolver" {
  count = var.inbound || length(var.forward) > 0 ? 1 : 0

  name        = "${var.name}-resolver"
  description = "Route 53 Resolver endpoints: DNS with our VPCs and the sites only"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.name_prefix}DNS Resolver" }
}

resource "aws_vpc_security_group_ingress_rule" "dns" {
  for_each = length(aws_security_group.resolver) == 0 ? {} : { for pair in setproduct(["tcp", "udp"], var.clients_cidrs) : "${pair[0]}-${pair[1]}" => pair }

  security_group_id = aws_security_group.resolver[0].id
  description       = "DNS from our VPCs and the sites"
  ip_protocol       = each.value[0]
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = each.value[1]
}

resource "aws_vpc_security_group_egress_rule" "dns" {
  for_each = length(aws_security_group.resolver) == 0 ? {} : { for pair in setproduct(["tcp", "udp"], var.clients_cidrs) : "${pair[0]}-${pair[1]}" => pair }

  security_group_id = aws_security_group.resolver[0].id
  description       = "DNS to the DNS servers of the sites and our VPCs"
  ip_protocol       = each.value[0]
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = each.value[1]
}

resource "aws_route53_resolver_endpoint" "inbound" {
  count = var.inbound ? 1 : 0

  name               = "${var.name}-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.resolver[0].id]

  dynamic "ip_address" {
    for_each = var.subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = { Name = "${local.name_prefix}DNS Resolver Inbound" }
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count = length(var.forward) > 0 || length(var.inbound_domains) > 0 ? 1 : 0

  name               = "${var.name}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.resolver[0].id]

  dynamic "ip_address" {
    for_each = var.subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = { Name = "${local.name_prefix}DNS Resolver Outbound" }
}

resource "aws_route53_resolver_rule" "forward" {
  for_each = var.forward

  name                 = "${var.name}-${replace(each.key, ".", "-")}"
  domain_name          = each.key
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = each.value
    content {
      ip = target_ip.value
    }
  }

  tags = { Name = "${local.name_prefix}DNS Forward ${each.key}", Domain = each.key }
}

resource "aws_route53_resolver_rule" "inbound" {
  for_each = toset(var.inbound_domains)

  name                 = "${var.name}-${replace(each.key, ".", "-")}"
  domain_name          = each.key
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = aws_route53_resolver_endpoint.inbound[0].ip_address
    content {
      ip = target_ip.value.ip
    }
  }

  tags = { Name = "${local.name_prefix}DNS Forward ${each.key}", Domain = each.key }
}
