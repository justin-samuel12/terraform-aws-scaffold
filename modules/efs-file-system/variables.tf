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

variable "tags" {
  description = "The file system's tags; Backup = standard puts it in the environment's AWS Backup plan. Name is the file system's name."
  type        = map(string)
  default     = {}
}

variable "mount_targets" {
  description = "Key -> the arguments of aws_efs_mount_target: subnet_id and security_groups, one per zone."
  type = map(object({
    subnet_id       = string
    security_groups = list(string)
  }))

  validation {
    condition     = length(var.mount_targets) >= 2
    error_message = "A file system needs mount targets in at least two zones."
  }
}

variable "access_points" {
  description = "Access point name -> the arguments of aws_efs_access_point: posix_user (uid, gid, secondary_gids), root_directory (path, and creation_info with owner_uid, owner_gid and permissions when the directory is to be created), tags."
  type = map(object({
    posix_user = object({
      uid            = number
      gid            = number
      secondary_gids = optional(list(number))
    })
    root_directory = object({
      path = string
      creation_info = optional(object({
        owner_uid   = number
        owner_gid   = number
        permissions = string
      }))
    })
    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for a in var.access_points : startswith(a.root_directory.path, "/") && (a.root_directory.creation_info == null || can(regex("^0[0-7]{3}$", try(a.root_directory.creation_info.permissions, ""))))])
    error_message = "An access point's path starts with /, and creation_info's permissions are octal such as 0750."
  }
}
