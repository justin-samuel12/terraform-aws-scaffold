data "aws_region" "current" {}

# Gateway endpoints are routes, free, and need no security group.
resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = { Name = "endpoint-${each.key}" }
}

# Interface endpoints answer at the service's usual name inside the VPC (private DNS), so agents need no configuration.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "endpoint-${each.key}" }

  lifecycle {
    precondition {
      condition     = length(var.subnet_ids) >= 2
      error_message = "Interface endpoints need a subnet in at least two zones."
    }
  }
}

resource "aws_security_group" "endpoints" {
  count = length(var.interface) > 0 ? 1 : 0

  name        = "endpoints"
  description = "Interface endpoints: HTTPS from inside the VPC only"
  vpc_id      = var.vpc_id

  tags = { Name = "endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints" {
  count = length(var.interface) > 0 ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr

  tags = { Name = "endpoints-in" }
}
