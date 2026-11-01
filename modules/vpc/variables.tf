variable "name" {
  description = "Name tag of the VPC, for example vpc-01. Subnets and route tables are named from it."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9]{2}$", var.name))
    error_message = "name must be vpc-NN, for example vpc-01 (docs/conventions.md)."
  }
}

variable "cidr_block" {
  description = "The VPC's CIDR, from the ip-plan module."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR."
  }
}

variable "availability_zone_ids" {
  description = "Availability zone IDs (use2-az1), the same physical zones in every account; in the same order as each tier's cidrs."
  type        = list(string)

  validation {
    condition     = length(var.availability_zone_ids) >= 2 && length(distinct(var.availability_zone_ids)) == length(var.availability_zone_ids) && alltrue([for zone in var.availability_zone_ids : can(regex("^[a-z]+[0-9]+-az[0-9]+$", zone))])
    error_message = "availability_zone_ids needs at least two distinct zone IDs, such as use2-az1."
  }
}

variable "subnets" {
  description = "Tier name -> one CIDR per availability zone, and where the tier's default route goes: internet, nat, transit or none."
  type = map(object({
    cidrs          = list(string)
    default_route  = string
    transit_routes = optional(list(string), [])
    reserved_cidrs = optional(list(string), [])
  }))

  validation {
    condition     = alltrue([for s in var.subnets : contains(["internet", "nat", "transit", "none"], s.default_route)])
    error_message = "default_route must be internet, nat, transit or none."
  }

  validation {
    condition     = alltrue([for s in var.subnets : length(s.cidrs) == length(var.availability_zone_ids)])
    error_message = "Every tier needs exactly one CIDR per availability zone."
  }
}

variable "nat_gateway_subnets" {
  description = "The tier that holds one NAT gateway per availability zone; required when a tier's default_route is nat."
  type        = string
  default     = null

  validation {
    condition = (
      var.nat_gateway_subnets == null
      ? !anytrue([for s in var.subnets : s.default_route == "nat"])
      : try(var.subnets[var.nat_gateway_subnets].default_route == "internet", false)
    )
    error_message = "A nat default_route needs nat_gateway_subnets, and that tier must route to the internet."
  }
}

variable "transit_gateway" {
  description = "Attach the VPC to a Transit Gateway: its id, the tier holding the attachment, the route table to associate with and the route tables to propagate into."
  type = object({
    id                          = string
    subnets                     = string
    association_route_table_id  = string
    propagation_route_table_ids = optional(map(string), {})
    appliance_mode              = optional(bool, false)
  })
  default = null

  validation {
    condition = (
      var.transit_gateway == null
      ? !anytrue([for s in var.subnets : s.default_route == "transit" || length(s.transit_routes) > 0])
      : contains(keys(var.subnets), var.transit_gateway.subnets)
    )
    error_message = "Routes to the Transit Gateway need transit_gateway, and its subnets must name an existing tier."
  }
}

variable "flow_log_retention_days" {
  description = "How long the VPC's flow logs are kept in CloudWatch Logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a retention CloudWatch Logs accepts, such as 90, 365 or 731."
  }
}
