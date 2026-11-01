variable "name" {
  description = "Name prefix for the endpoints and rules, for example dns-01."
  type        = string

  validation {
    condition     = can(regex("^dns-[0-9]{2}$", var.name))
    error_message = "name must be dns-NN, for example dns-01 (docs/conventions.md)."
  }
}

variable "vpc_id" {
  description = "The hub's egress VPC, which holds the endpoints."
  type        = string
}

variable "subnet_ids" {
  description = "One subnet per zone for the endpoints' network interfaces: the hub's dns tier."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Resolver endpoints need a subnet in at least two zones."
  }
}

variable "clients_cidrs" {
  description = "Who may query the inbound endpoint, and where the outbound endpoint may send: our VPCs and HQ."
  type        = list(string)
}

variable "inbound" {
  description = "Build an inbound endpoint, so HQ can resolve names in AWS."
  type        = bool
  default     = false
}

variable "forward" {
  description = "Domain -> the DNS server IPs at HQ that answer for it; any entry builds the outbound endpoint and one forwarding rule per domain."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue(flatten([for domain, ips in var.forward : concat([length(ips) > 0], [for ip in ips : can(cidrhost("${ip}/32", 0))])]))
    error_message = "Each domain needs at least one DNS server IP."
  }
}
