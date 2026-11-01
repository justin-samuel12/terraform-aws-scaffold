variable "certificates" {
  description = "Certificate name -> its domain, any other names on it, and the public hosted zone its validation records go in."
  type = map(object({
    domain            = string
    alternative_names = optional(list(string), [])
    zone              = string
  }))

  validation {
    condition     = alltrue([for c in var.certificates : alltrue([for d in concat([c.domain], c.alternative_names) : can(regex("^(\\*\\.)?[a-z0-9-]+(\\.[a-z0-9-]+)+$", d))])])
    error_message = "Domains are lowercase names such as app.example.com, optionally a *. wildcard."
  }

  validation {
    condition     = alltrue([for c in var.certificates : alltrue([for d in concat([c.domain], c.alternative_names) : d == c.zone || endswith(d, ".${c.zone}")])])
    error_message = "Every name on a certificate must be in its zone, so the zone can prove it."
  }
}
