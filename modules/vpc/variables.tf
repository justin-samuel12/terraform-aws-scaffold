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
      ? !anytrue([for s in var.subnets : s.default_route == "nat"]) && !anytrue([for r in var.routes : r.nat_gateway_id != null])
      : try(var.subnets[var.nat_gateway_subnets].default_route == "internet", false) || anytrue([for r in var.routes : r.tier == var.nat_gateway_subnets && r.destination_cidr_block == "0.0.0.0/0" && r.gateway_id == "own"])
    )
    error_message = "A nat default_route, or a route to nat_gateway_id own, needs nat_gateway_subnets, and that tier must route to the internet."
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
    security_group_referencing  = optional(bool, false)
    route_here                  = optional(bool, true)
    shared                      = optional(bool, false)
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

variable "transit_gateway_accepted" {
  description = "When the gateway is another account's: its acceptance of the attachment, so routes to the gateway wait for it."
  type        = string
  default     = null
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

variable "routes" {
  description = "Route name -> an aws_route in every route table of a tier: destination_cidr_block and exactly one target. gateway_id own is this VPC's internet gateway and nat_gateway_id own the NAT gateway in the subnet's own zone; any other value is an id (a peering connection's, a Transit Gateway's)."
  type = map(object({
    tier                      = string
    destination_cidr_block    = string
    gateway_id                = optional(string)
    nat_gateway_id            = optional(string)
    vpc_peering_connection_id = optional(string)
    transit_gateway_id        = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in var.routes : contains(keys(var.subnets), r.tier) && can(cidrnetmask(r.destination_cidr_block))])
    error_message = "A route names a tier of this VPC and an IPv4 destination_cidr_block."
  }

  validation {
    condition     = alltrue([for r in var.routes : length(compact([r.gateway_id, r.nat_gateway_id, r.vpc_peering_connection_id, r.transit_gateway_id])) == 1])
    error_message = "A route has exactly one target: gateway_id, nat_gateway_id, vpc_peering_connection_id or transit_gateway_id."
  }

  validation {
    condition     = alltrue([for r in var.routes : (r.gateway_id == null || r.gateway_id == "own") && (r.nat_gateway_id == null || r.nat_gateway_id == "own")])
    error_message = "gateway_id and nat_gateway_id are own: this VPC's internet gateway, and the NAT gateway in the subnet's zone."
  }
}

variable "network_acls" {
  description = "Tier -> an aws_network_acl on all of that tier's subnets, with its ingress and egress rules as the resource writes them. A tier left out keeps the VPC's default network ACL."
  type = map(object({
    ingress = optional(list(object({
      rule_no    = number
      action     = string
      protocol   = string
      cidr_block = string
      from_port  = optional(number, 0)
      to_port    = optional(number, 0)
      icmp_type  = optional(number)
      icmp_code  = optional(number)
    })), [])
    egress = optional(list(object({
      rule_no    = number
      action     = string
      protocol   = string
      cidr_block = string
      from_port  = optional(number, 0)
      to_port    = optional(number, 0)
      icmp_type  = optional(number)
      icmp_code  = optional(number)
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for tier in keys(var.network_acls) : contains(keys(var.subnets), tier)])
    error_message = "A network ACL names a tier of this VPC."
  }

  validation {
    condition = alltrue(flatten([for acl in var.network_acls : [
      for r in concat(acl.ingress, acl.egress) : contains(["allow", "deny"], r.action) && r.rule_no >= 1 && r.rule_no <= 32766 && floor(r.rule_no) == r.rule_no && can(cidrnetmask(r.cidr_block))
    ]]))
    error_message = "A network ACL rule has a whole rule_no from 1 to 32766, an action of allow or deny, and an IPv4 cidr_block."
  }

  validation {
    condition = alltrue(flatten([for acl in var.network_acls : [
      for rules in [acl.ingress, acl.egress] : length(distinct([for r in rules : r.rule_no])) == length(rules)
    ]]))
    error_message = "Each rule_no is used once per direction in a network ACL."
  }
}
