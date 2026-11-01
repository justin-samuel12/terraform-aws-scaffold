variable "lists" {
  description = "Prefix list name -> its entries, each a CIDR and a description."
  type = map(list(object({
    cidr        = string
    description = string
  })))

  validation {
    condition     = alltrue([for name in keys(var.lists) : can(regex("^[a-z][a-z0-9-]*$", name))])
    error_message = "Prefix list names are lowercase letters, digits and hyphens."
  }

  validation {
    condition     = alltrue(flatten([for entries in var.lists : [for e in entries : can(cidrnetmask(e.cidr)) && trimspace(e.description) != ""]]))
    error_message = "Every entry needs an IPv4 CIDR and a description."
  }

  validation {
    condition     = alltrue([for entries in var.lists : length(entries) > 0 && length(distinct([for e in entries : e.cidr])) == length(entries)])
    error_message = "A prefix list needs at least one entry, and no CIDR twice."
  }
}

variable "headroom" {
  description = "Entries each list can grow by before its size has to change; a rule using a list counts its maximum against the security group's limit."
  type        = number
  default     = 5
}
