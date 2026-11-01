variable "vpc_id" {
  description = "The VPC every group is created in."
  type        = string
}

variable "internal_cidr" {
  description = "The range the hubs route between VPCs; the default egress allows all of it."
  type        = string
  default     = "10.0.0.0/8"
}

variable "groups" {
  description = "Group name -> description, whether it fronts a public load balancer, and its rules. A rule names exactly one of group (another group here, or self), cidr or prefix_list (an id). egress null = internal traffic and HTTPS out."
  type = map(object({
    description   = string
    load_balancer = optional(bool, false)
    ingress = list(object({
      description = string
      protocol    = string
      from_port   = optional(number)
      to_port     = optional(number)
      group       = optional(string)
      cidr        = optional(string)
      prefix_list = optional(string)
    }))
    egress = optional(list(object({
      description = string
      protocol    = string
      from_port   = optional(number)
      to_port     = optional(number)
      group       = optional(string)
      cidr        = optional(string)
      prefix_list = optional(string)
    })))
  }))

  validation {
    condition     = alltrue([for name in keys(var.groups) : can(regex("^[a-z][a-z0-9-]{0,62}$", name))])
    error_message = "Group names are lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : [for r in concat(g.ingress, coalesce(g.egress, [])) : length(compact([r.group, r.cidr, r.prefix_list])) == 1]]))
    error_message = "Every rule names exactly one of group, cidr or prefix_list."
  }

  validation {
    condition = alltrue(flatten([for g in var.groups : [
      for r in concat(g.ingress, coalesce(g.egress, [])) : r.group == null || r.group == "self" || contains(keys(var.groups), coalesce(r.group, "-"))
    ]]))
    error_message = "A rule's group must be self or another group in this stack."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : [for r in concat(g.ingress, coalesce(g.egress, [])) : contains(["tcp", "udp", "icmp", "-1"], r.protocol)]]))
    error_message = "protocol must be tcp, udp, icmp or -1 (all)."
  }

  validation {
    condition = alltrue(flatten([for g in var.groups : [
      for r in concat(g.ingress, coalesce(g.egress, [])) :
      r.protocol == "-1" ? (r.from_port == null && r.to_port == null) : (r.from_port != null && r.to_port != null && try(r.from_port >= 0 && r.to_port <= 65535 && r.from_port <= r.to_port, false))
    ]]))
    error_message = "Ports run from 0 to 65535, from_port no higher than to_port; a rule for all protocols has no ports."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : [for r in concat(g.ingress, coalesce(g.egress, [])) : trimspace(r.description) != ""]]))
    error_message = "Every rule needs a description."
  }

  validation {
    condition = alltrue(flatten([for g in var.groups : [
      for r in g.ingress : r.cidr != "0.0.0.0/0" || (g.load_balancer && r.protocol == "tcp" && r.from_port == 443 && r.to_port == 443)
    ]]))
    error_message = "Inbound from 0.0.0.0/0 is allowed only on TCP 443, and only to a group marked load_balancer."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : [for r in concat(g.ingress, coalesce(g.egress, [])) : r.cidr == null || can(cidrnetmask(r.cidr))]]))
    error_message = "A rule's cidr must be an IPv4 CIDR."
  }
}
