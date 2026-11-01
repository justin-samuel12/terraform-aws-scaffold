variable "name" {
  description = "Name tag of the Transit Gateway, for example tgw-01. Route tables are named from it."
  type        = string

  validation {
    condition     = can(regex("^tgw-[0-9]{2}$", var.name))
    error_message = "name must be tgw-NN, for example tgw-01 (docs/conventions.md)."
  }
}

variable "amazon_side_asn" {
  description = "Private BGP ASN for the Amazon side; each hub needs its own."
  type        = number

  validation {
    condition     = (var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534) || (var.amazon_side_asn >= 4200000000 && var.amazon_side_asn <= 4294967294)
    error_message = "amazon_side_asn must be a private ASN."
  }
}

variable "route_tables" {
  description = "Route tables to create, by isolation level, for example restricted, standard, shared."
  type        = set(string)

  validation {
    condition     = alltrue([for name in var.route_tables : can(regex("^[a-z][a-z0-9-]*$", name))])
    error_message = "Route table names are lowercase words, for example restricted."
  }
}

variable "routes" {
  description = "Static routes: key -> route table, destination CIDR, and the attachment to send it to (or blackhole)."
  type = map(object({
    route_table   = string
    destination   = string
    attachment_id = optional(string)
    blackhole     = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for route in var.routes : contains(var.route_tables, route.route_table)])
    error_message = "Every route must name one of route_tables."
  }

  validation {
    condition     = alltrue([for route in var.routes : (route.attachment_id == null) == route.blackhole])
    error_message = "A route needs either an attachment_id or blackhole = true, not both."
  }
}
