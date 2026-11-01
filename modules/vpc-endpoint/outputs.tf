output "ids" {
  description = "Service -> endpoint id, gateway and interface alike."
  value       = merge({ for s, e in aws_vpc_endpoint.gateway : s => e.id }, { for s, e in aws_vpc_endpoint.interface : s => e.id })
}
