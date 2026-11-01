variable "name" {
  description = "The database's identifier."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "engine" {
  description = "mysql, postgres or mariadb."
  type        = string

  validation {
    condition     = contains(["mysql", "postgres", "mariadb"], var.engine)
    error_message = "engine must be mysql, postgres or mariadb."
  }
}

variable "engine_version" {
  description = "The major version (8.0, 16, 10.11); minor versions upgrade themselves in the maintenance window."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version is a major version such as 8.0 or 16."
  }
}

variable "instance_class" {
  description = "Such as db.t4g.medium or db.r6g.large."
  type        = string
}

variable "storage" {
  description = "Starting storage in GB."
  type        = number
}

variable "max_storage" {
  description = "Storage grows by itself up to this many GB."
  type        = number
}

variable "multi_az" {
  description = "A standby in another zone that takes over by itself."
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "The data tier's subnets, one per zone."
  type        = list(string)
}

variable "security_group_ids" {
  description = "The database's security groups."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "The environment's data key: storage, the password secret and Performance Insights."
  type        = string
}

variable "monitoring_role_arn" {
  description = "The role enhanced monitoring publishes with."
  type        = string
}

variable "backup_window" {
  description = "Daily automated backup window, UTC."
  type        = string
  default     = "06:00-07:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window, UTC; after the backup window."
  type        = string
  default     = "sun:07:30-sun:08:30"
}
