variable "records" {
  description = "Record key -> its zone, full name, and either an alias (a load balancer's DNS name and zone) or a type with values."
  type = map(object({
    zone_id = string
    name    = string
    type    = optional(string, "A")
    ttl     = optional(number, 300)
    values  = optional(list(string), [])
    alias = optional(object({
      name    = string
      zone_id = string
    }))
  }))

  validation {
    condition     = alltrue([for r in var.records : (r.alias == null) != (length(r.values) == 0) && contains(["A", "AAAA", "CNAME", "TXT"], r.type)])
    error_message = "A record is either an alias or has values, and its type is A, AAAA, CNAME or TXT."
  }
}
