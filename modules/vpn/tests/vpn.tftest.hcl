mock_provider "aws" {}

variables {
  name                        = "vpn-01"
  transit_gateway_id          = "tgw-0123456789abcdef0"
  customer_gateway            = { ip_address = "203.0.113.10", bgp_asn = 65010 }
  association_route_table_id  = "tgw-rtb-shared"
  propagation_route_table_ids = { restricted = "tgw-rtb-restricted", standard = "tgw-rtb-standard", shared = "tgw-rtb-shared" }
}

run "vpn" {
  command = plan

  assert {
    condition     = aws_vpn_connection.vpn_connection.static_routes_only == false
    error_message = "The VPN uses BGP so routes fail over on their own."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_propagation.route_table_propagations) == 3
    error_message = "On-premises routes propagate into every listed route table."
  }

  assert {
    condition     = aws_vpn_connection.vpn_connection.tunnel1_ike_versions == toset(["ikev2"]) && aws_vpn_connection.vpn_connection.tunnel2_ike_versions == toset(["ikev2"])
    error_message = "Both tunnels accept only IKEv2."
  }

  assert {
    condition     = !contains(aws_vpn_connection.vpn_connection.tunnel1_phase1_encryption_algorithms, "AES128") && !contains(aws_vpn_connection.vpn_connection.tunnel2_phase2_integrity_algorithms, "SHA1")
    error_message = "Neither tunnel can be negotiated down to AES-128 or SHA-1."
  }

  assert {
    condition     = aws_vpn_connection.vpn_connection.tunnel1_log_options[0].cloudwatch_log_options[0].log_enabled && aws_vpn_connection.vpn_connection.tunnel2_log_options[0].cloudwatch_log_options[0].log_enabled
    error_message = "Both tunnels log to CloudWatch."
  }

  assert {
    condition     = aws_customer_gateway.customer_gateway.tags.Name == "vpn-01-cgw"
    error_message = "The customer gateway is named <vpn>-cgw."
  }
}

run "rejects_bad_ip" {
  command = plan

  variables {
    customer_gateway = { ip_address = "hq.example.com", bgp_asn = 65010 }
  }

  expect_failures = [var.customer_gateway]
}
