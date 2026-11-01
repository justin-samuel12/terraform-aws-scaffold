variable "name" {
  description = "The file system's name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens."
  }
}

variable "kms_key_arn" {
  description = "The environment's data key."
  type        = string
}

variable "subnet_ids" {
  description = "One subnet per zone for the mount targets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A file system needs mount targets in at least two zones."
  }
}

variable "security_group_ids" {
  description = "The mount targets' security groups."
  type        = list(string)
}

variable "access_points" {
  description = "Access point name -> the directory it exposes and the POSIX user and permissions clients get there."
  type = map(object({
    path        = string
    uid         = number
    gid         = number
    permissions = optional(string, "0750")
  }))
  default = {}

  validation {
    condition     = alltrue([for a in var.access_points : startswith(a.path, "/") && can(regex("^0[0-7]{3}$", a.permissions))])
    error_message = "An access point's path starts with /, and its permissions are octal such as 0750."
  }
}
