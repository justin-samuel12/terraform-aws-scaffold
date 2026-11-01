resource "aws_security_group" "resolver" {
  count = var.inbound || length(var.forward) > 0 ? 1 : 0

  name        = "${var.name}-resolver"
  description = "Route 53 Resolver endpoints: DNS with our VPCs and HQ only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-resolver" }
}

resource "aws_vpc_security_group_ingress_rule" "dns" {
  for_each = length(aws_security_group.resolver) == 0 ? {} : { for pair in setproduct(["tcp", "udp"], var.clients_cidrs) : "${pair[0]}-${pair[1]}" => pair }

  security_group_id = aws_security_group.resolver[0].id
  description       = "DNS from our VPCs and HQ"
  ip_protocol       = each.value[0]
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = each.value[1]
}

resource "aws_vpc_security_group_egress_rule" "dns" {
  for_each = length(aws_security_group.resolver) == 0 ? {} : { for pair in setproduct(["tcp", "udp"], var.clients_cidrs) : "${pair[0]}-${pair[1]}" => pair }

  security_group_id = aws_security_group.resolver[0].id
  description       = "DNS to HQ's servers and our VPCs"
  ip_protocol       = each.value[0]
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = each.value[1]
}

# HQ asks this endpoint for names in AWS (private hosted zones, VPC names).
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

  tags = { Name = "${var.name}-inbound" }
}

# AWS asks HQ, through this endpoint, for the domains in forward (Active Directory).
resource "aws_route53_resolver_endpoint" "outbound" {
  count = length(var.forward) > 0 ? 1 : 0

  name               = "${var.name}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.resolver[0].id]

  dynamic "ip_address" {
    for_each = var.subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = { Name = "${var.name}-outbound" }
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

  tags = { Name = "${var.name}-${replace(each.key, ".", "-")}", Domain = each.key }
}
