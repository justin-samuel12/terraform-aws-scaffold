variable "name" {
  description = "Name tag of the peering, for example tgw-peering-01."
  type        = string

  validation {
    condition     = can(regex("^tgw-peering-[0-9]{2}$", var.name))
    error_message = "name must be tgw-peering-NN, for example tgw-peering-01 (docs/conventions.md)."
  }
}

variable "requester" {
  description = "The side that requests the peering: its region, Transit Gateway, the route table the peering is associated with, and the CIDRs it sends across."
  type = object({
    region             = string
    transit_gateway_id = string
    route_table_id     = string
    routes             = map(list(string))
  })
}

variable "accepter" {
  description = "The side that accepts, described the same way as requester."
  type = object({
    region             = string
    transit_gateway_id = string
    route_table_id     = string
    routes             = map(list(string))
  })

  validation {
    condition     = var.accepter.region != var.requester.region
    error_message = "Peering joins hubs in two different regions."
  }
}
