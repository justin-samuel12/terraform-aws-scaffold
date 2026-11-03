variable "engine" {
  description = "The RDS Custom engine the version is for: custom-sqlserver-ee, custom-sqlserver-se, custom-sqlserver-web or custom-sqlserver-dev."
  type        = string

  validation {
    condition     = contains(["custom-sqlserver-ee", "custom-sqlserver-se", "custom-sqlserver-web", "custom-sqlserver-dev"], var.engine)
    error_message = "engine must be custom-sqlserver-ee, custom-sqlserver-se, custom-sqlserver-web or custom-sqlserver-dev."
  }
}

variable "engine_version" {
  description = "SQL Server's version on the image and a name of our own after it, such as 16.00.4185.3.dbamp-v1; databases name it as their engine_version."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\.[A-Za-z0-9_-]+$", var.engine_version)) && !can(regex("\\.v[0-9]+$", var.engine_version))
    error_message = "engine_version is SQL Server's own version and a name of our own, such as 16.00.4185.3.dbamp-v1; a name ending in .v<number> is AWS's."
  }
}

variable "source_image_id" {
  description = "The AMI the version is made from: Windows Server with SQL Server installed from our own media, built as AWS's RDS Custom guide describes."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.source_image_id))
    error_message = "source_image_id is an AMI ID, such as ami-0123456789abcdef0."
  }
}

variable "description" {
  description = "What is on the image, for whoever lists the versions later."
  type        = string
}
