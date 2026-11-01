variable "public" {
  description = "Public hosted zones: domains this account answers for on the internet."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for z in var.public : can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", z))])
    error_message = "Zone names are lowercase domains such as example.com."
  }
}

variable "private" {
  description = "Private hosted zone name -> the VPC it is created with. Every other VPC associates itself afterwards, from its own network stack."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for z in keys(var.private) : can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", z))])
    error_message = "Zone names are lowercase domains, such as internal.example.com or 42.10.in-addr.arpa."
  }
}
