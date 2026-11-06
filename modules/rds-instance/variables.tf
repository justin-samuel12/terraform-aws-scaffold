variable "name" {
  description = "The database's identifier."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "engine" {
  description = "mysql, postgres or mariadb; SQL Server as sqlserver-ex, -web, -se or -ee; RDS Custom for SQL Server as custom-sqlserver-ee, -se, -web or -dev."
  type        = string

  validation {
    condition     = contains(["mysql", "postgres", "mariadb", "sqlserver-ex", "sqlserver-web", "sqlserver-se", "sqlserver-ee", "custom-sqlserver-ee", "custom-sqlserver-se", "custom-sqlserver-web", "custom-sqlserver-dev"], var.engine)
    error_message = "engine must be mysql, postgres, mariadb, sqlserver-ex, sqlserver-web, sqlserver-se, sqlserver-ee, custom-sqlserver-ee, custom-sqlserver-se, custom-sqlserver-web or custom-sqlserver-dev."
  }
}

variable "engine_version" {
  description = "The major version (8.0, 16, 10.11; SQL Server 16.00), or SQL Server's full version (16.00.4185.3.v1); RDS Custom takes a full version, AWS's or one of our own."
  type        = string

  validation {
    condition = (
      startswith(var.engine, "custom-") ? can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\.[A-Za-z0-9_-]+$", var.engine_version)) :
      startswith(var.engine, "sqlserver-") ? can(regex("^[0-9]+\\.00(\\.[0-9]+\\.[0-9]+\\.v[0-9]+)?$", var.engine_version)) :
      can(regex("^[0-9]+(\\.[0-9]+)?$", var.engine_version))
    )
    error_message = "engine_version is a major version such as 8.0 or 16; for SQL Server 16.00 or a full version such as 16.00.4185.3.v1; for RDS Custom always a full version."
  }
}

variable "instance_class" {
  description = "Such as db.t4g.medium or db.r6g.large."
  type        = string
}

variable "allocated_storage" {
  description = "Starting storage in GB."
  type        = number
}

variable "max_allocated_storage" {
  description = "Storage grows by itself up to this many GB; null, as AWS has it, for none. RDS Custom does not grow by itself."
  type        = number
  default     = null
}

variable "multi_az" {
  description = "A standby in another zone that takes over by itself; null, as AWS has it, for none."
  type        = bool
  default     = null
}

variable "subnet_ids" {
  description = "The data tier's subnets, one per zone."
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "The database's security groups, by ID."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "The environment's data key: storage, the password secret and Performance Insights."
  type        = string
}

variable "monitoring_role_arn" {
  description = "The role enhanced monitoring publishes with; null for RDS Custom, which has none."
  type        = string
  default     = null

  validation {
    condition     = startswith(var.engine, "custom-") || var.monitoring_role_arn != null
    error_message = "Every database but RDS Custom needs monitoring_role_arn."
  }
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

variable "timezone" {
  description = "SQL Server only: the server's Windows time zone, such as Eastern Standard Time; null = UTC. Fixed once created."
  type        = string
  default     = null

  validation {
    condition     = var.timezone == null || can(regex("sqlserver-", var.engine))
    error_message = "timezone is for SQL Server only."
  }
}

variable "character_set_name" {
  description = "SQL Server only: the server collation, such as SQL_Latin1_General_CP1_CI_AS (the default). Fixed once created."
  type        = string
  default     = null

  validation {
    condition     = var.character_set_name == null || can(regex("sqlserver-", var.engine))
    error_message = "character_set_name (the collation) is for SQL Server only."
  }
}

variable "option" {
  description = "RDS for SQL Server only: the option list of the database's aws_db_option_group, each option_name with its port, version, vpc_security_group_memberships (IDs) and option_settings (name, value)."
  type = list(object({
    option_name                    = string
    port                           = optional(number)
    version                        = optional(string)
    vpc_security_group_memberships = optional(list(string))
    option_settings = optional(list(object({
      name  = string
      value = string
    })), [])
  }))
  default = []

  validation {
    condition     = length(var.option) == 0 || startswith(var.engine, "sqlserver-")
    error_message = "Options are for RDS for SQL Server only."
  }
}

variable "domain" {
  description = "SQL Server only: an AWS Managed Microsoft AD directory ID to join (d-...), with domain_iam_role_name."
  type        = string
  default     = null
}

variable "domain_iam_role_name" {
  description = "The role RDS joins the AWS Managed Microsoft AD directory with."
  type        = string
  default     = null
}

variable "domain_fqdn" {
  description = "SQL Server only: a self-managed Active Directory's domain to join, such as corp.example.com (and RDS Custom's way into any directory)."
  type        = string
  default     = null
}

variable "domain_ou" {
  description = "The organizational unit the database's computer account goes in, such as OU=RDS,DC=corp,DC=example,DC=com."
  type        = string
  default     = null
}

variable "domain_auth_secret_arn" {
  description = "The Secrets Manager secret holding the service account that joins the domain."
  type        = string
  default     = null
}

variable "domain_dns_ips" {
  description = "Two domain controllers' addresses, used as DNS."
  type        = list(string)
  default     = null
}

variable "custom_iam_instance_profile" {
  description = "RDS Custom only: the instance profile its server runs with, named AWSRDSCustom..."
  type        = string
  default     = null

  validation {
    condition     = startswith(var.engine, "custom-") == (var.custom_iam_instance_profile != null) && (var.custom_iam_instance_profile == null || startswith(coalesce(var.custom_iam_instance_profile, "-"), "AWSRDSCustom"))
    error_message = "RDS Custom needs custom_iam_instance_profile, an instance profile whose name starts with AWSRDSCustom; nothing else takes one."
  }
}

variable "license_model" {
  description = "license-included or bring-your-own-media (RDS Custom, from a version of our own); null, as AWS has it."
  type        = string
  default     = null
}

variable "password_wo_version" {
  description = "RDS Custom only: the version of the write-only dbadmin password. Raise it by one to set a new password on the database and in its secret together."
  type        = number
  default     = null

  validation {
    condition     = startswith(var.engine, "custom-") ? try(var.password_wo_version >= 1 && floor(var.password_wo_version) == var.password_wo_version, false) : var.password_wo_version == null
    error_message = "RDS Custom needs password_wo_version, a whole number from 1; nothing else takes one."
  }
}

variable "tags" {
  description = "Tags from the file, on everything this module builds; the ones it sets itself (Name and the like) win."
  type        = map(string)
  default     = {}
}
