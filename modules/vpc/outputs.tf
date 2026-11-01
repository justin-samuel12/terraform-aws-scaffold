output "vpc_id" {
  description = "The VPC's id."
  value       = aws_vpc.vpc.id
}

output "cidr_block" {
  description = "The VPC's CIDR."
  value       = aws_vpc.vpc.cidr_block
}

output "subnet_ids" {
  description = "Tier -> subnet ids, in availability_zone_ids order."
  value       = { for tier in keys(var.subnets) : tier => [for zone in var.availability_zone_ids : aws_subnet.subnets["${tier}-${zone}"].id] }
}

output "route_table_ids" {
  description = "Tier -> route table ids, in availability_zone_ids order."
  value       = { for tier in keys(var.subnets) : tier => [for zone in var.availability_zone_ids : aws_route_table.route_tables["${tier}-${zone}"].id] }
}

output "transit_gateway_attachment_id" {
  description = "The Transit Gateway attachment's id, or null when not attached."
  value       = one(aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment[*].id)
}

output "subnets" {
  description = "Subnet name (its Subnet tag, such as data-az1) -> id, CIDR and zone ID: the names compute uses."
  value = {
    for key, subnet in local.subnets : "${subnet.tier}-${split("-", subnet.zone)[1]}" => {
      id   = aws_subnet.subnets[key].id
      cidr = subnet.cidr
      zone = subnet.zone
    }
  }
}
