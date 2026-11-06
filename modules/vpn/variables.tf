variable "name" {
  description = "The site this VPN reaches, its name under sites in config/global.yml (office); with the device's address it names the tunnel log group and each Name tag (Shared - Office VPN 203.0.113.10), so a site with two links has two of each."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name))
    error_message = "name is the site's name: lowercase letters, digits and hyphens, such as office."
  }
}

variable "transit_gateway_id" {
  description = "The Transit Gateway the VPN terminates on."
  type        = string
}

variable "customer_gateway" {
  description = "The on-premises end: its public IP and BGP ASN."
  type = object({
    ip_address = string
    bgp_asn    = number
  })

  validation {
    condition     = can(cidrhost("${var.customer_gateway.ip_address}/32", 0))
    error_message = "customer_gateway.ip_address must be an IPv4 address."
  }
}

variable "association_route_table_id" {
  description = "The Transit Gateway route table the VPN attachment is associated with."
  type        = string
}

variable "propagation_route_table_ids" {
  description = "Route table name -> id that learn the on-premises routes over BGP."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "How long the tunnels' logs are kept in CloudWatch Logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention CloudWatch Logs accepts, such as 90, 365 or 731."
  }
}
