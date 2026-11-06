resource "aws_customer_gateway" "customer_gateway" {
  bgp_asn    = var.customer_gateway.bgp_asn
  ip_address = var.customer_gateway.ip_address
  type       = "ipsec.1"

  tags = { Name = "${local.name_prefix}${local.site} Customer Gateway ${var.customer_gateway.ip_address}" }
}

resource "aws_vpn_connection" "vpn_connection" {
  customer_gateway_id = aws_customer_gateway.customer_gateway.id
  transit_gateway_id  = var.transit_gateway_id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_ike_versions                 = local.ike_versions
  tunnel1_phase1_encryption_algorithms = local.encryption_algorithms
  tunnel1_phase1_integrity_algorithms  = local.integrity_algorithms
  tunnel1_phase1_dh_group_numbers      = local.dh_groups
  tunnel1_phase2_encryption_algorithms = local.encryption_algorithms
  tunnel1_phase2_integrity_algorithms  = local.integrity_algorithms
  tunnel1_phase2_dh_group_numbers      = local.dh_groups

  tunnel1_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.tunnel_logs.arn
      log_output_format = "json"
    }
  }

  tunnel2_ike_versions                 = local.ike_versions
  tunnel2_phase1_encryption_algorithms = local.encryption_algorithms
  tunnel2_phase1_integrity_algorithms  = local.integrity_algorithms
  tunnel2_phase1_dh_group_numbers      = local.dh_groups
  tunnel2_phase2_encryption_algorithms = local.encryption_algorithms
  tunnel2_phase2_integrity_algorithms  = local.integrity_algorithms
  tunnel2_phase2_dh_group_numbers      = local.dh_groups

  tunnel2_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.tunnel_logs.arn
      log_output_format = "json"
    }
  }

  tags = { Name = "${local.name_prefix}${local.site} VPN ${var.customer_gateway.ip_address}" }
}

resource "aws_cloudwatch_log_group" "tunnel_logs" {
  name              = "/vpn/tunnel-logs/${var.transit_gateway_id}/${var.name}/${var.customer_gateway.ip_address}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${local.name_prefix}${local.site} VPN Tunnel Logs ${var.customer_gateway.ip_address}" }
}

resource "aws_ec2_transit_gateway_route_table_association" "route_table_association" {
  transit_gateway_attachment_id  = aws_vpn_connection.vpn_connection.transit_gateway_attachment_id
  transit_gateway_route_table_id = var.association_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "route_table_propagations" {
  for_each = var.propagation_route_table_ids

  transit_gateway_attachment_id  = aws_vpn_connection.vpn_connection.transit_gateway_attachment_id
  transit_gateway_route_table_id = each.value
}
