variable "records" {
  description = "Record key -> the arguments of aws_route53_record: zone_id, name in full, type, and either ttl with records or an alias (name, zone_id, evaluate_target_health)."
  type = map(object({
    zone_id = string
    name    = string
    type    = string
    ttl     = optional(number)
    records = optional(list(string), [])
    alias = optional(object({
      name                   = string
      zone_id                = string
      evaluate_target_health = bool
    }))
  }))

  validation {
    condition     = alltrue([for r in var.records : r.alias == null ? r.ttl != null && length(r.records) > 0 : r.ttl == null && length(r.records) == 0])
    error_message = "A record is either an alias, or has a ttl and records."
  }

  validation {
    condition     = alltrue([for r in var.records : contains(["A", "AAAA", "CNAME", "TXT"], r.type)])
    error_message = "type is A, AAAA, CNAME or TXT."
  }
}
