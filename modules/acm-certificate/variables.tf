variable "certificates" {
  description = "Certificate name -> the arguments of aws_acm_certificate (domain_name, subject_alternative_names, validation_method, key_algorithm, tags) and validation_zone, the public hosted zone its DNS validation records go in."
  type = map(object({
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
    validation_method         = string
    key_algorithm             = string
    tags                      = optional(map(string), {})
    validation_zone           = string
  }))

  validation {
    condition     = alltrue([for c in var.certificates : alltrue([for d in concat([c.domain_name], c.subject_alternative_names) : can(regex("^(\\*\\.)?[a-z0-9-]+(\\.[a-z0-9-]+)+$", d))])])
    error_message = "Domains are lowercase names such as app.example.com, optionally a *. wildcard."
  }

  validation {
    condition     = alltrue([for c in var.certificates : alltrue([for d in concat([c.domain_name], c.subject_alternative_names) : d == c.validation_zone || endswith(d, ".${c.validation_zone}")])])
    error_message = "Every name on a certificate must be in its validation_zone, so the zone can prove it."
  }

  validation {
    condition     = alltrue([for c in var.certificates : c.validation_method == "DNS"])
    error_message = "validation_method is DNS: the validation records are written here, and the certificate renews by itself."
  }
}
