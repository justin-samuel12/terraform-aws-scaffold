output "ids" {
  description = "Endpoint name -> endpoint id."
  value       = { for name, e in aws_vpc_endpoint.endpoints : name => e.id }
}
