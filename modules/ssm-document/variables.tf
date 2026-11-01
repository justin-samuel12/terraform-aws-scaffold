variable "documents" {
  description = "Document name -> its type (Command, Automation, Session) and its content, which is written as YAML."
  type = map(object({
    type    = string
    content = any
  }))

  validation {
    condition     = alltrue([for name in keys(var.documents) : can(regex("^[A-Za-z0-9_.-]{3,128}$", name)) && !startswith(lower(name), "aws")])
    error_message = "Document names are 3 to 128 letters, digits, _ . and -, and may not start with AWS (reserved)."
  }

  validation {
    condition     = alltrue([for d in var.documents : contains(["Command", "Automation", "Session"], d.type)])
    error_message = "type is Command, Automation or Session."
  }
}
