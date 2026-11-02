output "transit_gateway_id" {
  description = "The Transit Gateway's id."
  value       = aws_ec2_transit_gateway.transit_gateway.id
}

output "route_table_ids" {
  description = "Route table name -> id."
  value       = { for name, table in aws_ec2_transit_gateway_route_table.route_tables : name => table.id }
}

output "transit_gateway_arn" {
  description = "The Transit Gateway's ARN, for sharing it with other accounts."
  value       = aws_ec2_transit_gateway.transit_gateway.arn
}
