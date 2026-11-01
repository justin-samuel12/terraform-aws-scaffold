output "vpn_connection_id" {
  description = "The VPN connection's id."
  value       = aws_vpn_connection.vpn_connection.id
}

output "transit_gateway_attachment_id" {
  description = "The VPN's Transit Gateway attachment id."
  value       = aws_vpn_connection.vpn_connection.transit_gateway_attachment_id
}

output "tunnel_addresses" {
  description = "The AWS end of each tunnel, for configuring the on-premises firewall."
  value       = [aws_vpn_connection.vpn_connection.tunnel1_address, aws_vpn_connection.vpn_connection.tunnel2_address]
}
