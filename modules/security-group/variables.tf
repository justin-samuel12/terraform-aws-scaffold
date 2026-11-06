variable "vpc_id" {
  description = "The VPC every group is created in."
  type        = string
}

variable "groups" {
  description = "Group name -> its aws_security_group arguments (description, tags) and its rules, each with the arguments of aws_vpc_security_group_ingress_rule or _egress_rule. A rule names exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id or referenced_security_group_id, which is a group in this module by name or any group's id. No egress means no traffic out."
  type = map(object({
    description = string
    tags        = optional(map(string), {})
    ingress = optional(list(object({
      description                  = string
      ip_protocol                  = string
      from_port                    = optional(number)
      to_port                      = optional(number)
      cidr_ipv4                    = optional(string)
      cidr_ipv6                    = optional(string)
      prefix_list_id               = optional(string)
      referenced_security_group_id = optional(string)
    })), [])
    egress = optional(list(object({
      description                  = string
      ip_protocol                  = string
      from_port                    = optional(number)
      to_port                      = optional(number)
      cidr_ipv4                    = optional(string)
      cidr_ipv6                    = optional(string)
      prefix_list_id               = optional(string)
      referenced_security_group_id = optional(string)
    })), [])
  }))

  validation {
    condition     = alltrue([for name in keys(var.groups) : can(regex("^[a-z][a-z0-9-]{0,62}$", name))])
    error_message = "Group names are lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : [for r in concat(g.ingress, g.egress) : length(compact([r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.referenced_security_group_id])) == 1]]))
    error_message = "Every rule names exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id or referenced_security_group_id."
  }

  validation {
    condition = alltrue(flatten([for g in var.groups : [
      for r in concat(g.ingress, g.egress) : r.referenced_security_group_id == null || contains(keys(var.groups), coalesce(r.referenced_security_group_id, "-")) || startswith(coalesce(r.referenced_security_group_id, "-"), "sg-")
    ]]))
    error_message = "referenced_security_group_id is a group in this stack, by name (its own name for traffic between its members), or a group's id."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : [for r in concat(g.ingress, g.egress) : contains(["tcp", "udp", "icmp", "icmpv6", "-1"], r.ip_protocol)]]))
    error_message = "ip_protocol is tcp, udp, icmp, icmpv6 or -1 (all)."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : concat([can(regex("^[a-zA-Z0-9. _:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", g.description))], [for r in concat(g.ingress, g.egress) : can(regex("^[a-zA-Z0-9. _:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", r.description))])]))
    error_message = "Descriptions are what AWS accepts on a security group and its rules: up to 255 letters, digits, spaces and ._-:/()#,@[]+=&;{}!$* only, so no apostrophes or quotes (write the hub egress, not the hub's egress)."
  }

  validation {
    condition = alltrue(flatten([for g in var.groups : [
      for r in concat(g.ingress, g.egress) :
      r.ip_protocol == "-1" ? (r.from_port == null && r.to_port == null) : contains(["icmp", "icmpv6"], r.ip_protocol) ? (r.from_port != null && r.to_port != null && try(r.from_port >= -1 && r.from_port <= 255 && r.to_port >= -1 && r.to_port <= 255, false)) : (r.from_port != null && r.to_port != null && try(r.from_port >= 0 && r.to_port <= 65535 && r.from_port <= r.to_port, false))
    ]]))
    error_message = "Ports run from 0 to 65535, from_port no higher than to_port; for icmp and icmpv6, from_port is the type and to_port the code, -1 for all; a rule for all protocols has no ports."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : [for r in concat(g.ingress, g.egress) : trimspace(r.description) != ""]]))
    error_message = "Every rule needs a description."
  }

  validation {
    condition = alltrue(flatten([for g in var.groups : [
      for r in g.ingress : !contains(["0.0.0.0/0", "::/0"], coalesce(r.cidr_ipv4, r.cidr_ipv6, "-")) || (r.ip_protocol == "tcp" && contains([80, 443], r.from_port) && r.to_port == r.from_port)
    ]]))
    error_message = "Inbound from the whole internet (0.0.0.0/0, ::/0) is allowed only on TCP 443, or 80 for the redirect to it."
  }

  validation {
    condition     = alltrue(flatten([for g in var.groups : [for r in concat(g.ingress, g.egress) : (r.cidr_ipv4 == null || can(cidrnetmask(r.cidr_ipv4))) && (r.cidr_ipv6 == null || can(cidrhost(r.cidr_ipv6, 0)))]]))
    error_message = "cidr_ipv4 is an IPv4 CIDR and cidr_ipv6 an IPv6 one."
  }
}
