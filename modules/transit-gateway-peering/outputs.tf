output "transit_gateway_attachment_id" {
  description = "The peering attachment's id (the same on both sides)."
  value       = aws_ec2_transit_gateway_peering_attachment_accepter.peering_attachment_accepter.transit_gateway_attachment_id
}
