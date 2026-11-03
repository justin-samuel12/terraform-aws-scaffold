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

variable "storage" {
  description = "Starting storage in GB."
  type        = number
}

variable "max_storage" {
  description = "Storage grows by itself up to this many GB; null for RDS Custom, which does not grow by itself."
  type        = number
  default     = null

  validation {
    condition     = startswith(var.engine, "custom-") == (var.max_storage == null)
    error_message = "max_storage is required, except for RDS Custom, which does not grow its storage by itself and takes none."
  }
}

variable "multi_az" {
  description = "A standby in another zone that takes over by itself."
  type        = bool
  default     = true

  validation {
    condition     = !var.multi_az || (var.engine != "sqlserver-ex" && (var.engine != "sqlserver-web" || (split(".", var.engine_version)[0] == "16" && try(tonumber(split(".", var.engine_version)[2]) >= 4215, true))))
    error_message = "SQL Server Express cannot be Multi-AZ, and Web edition only from SQL Server 2022 (16.00.4215.2 on)."
  }
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

variable "options" {
  description = "RDS for SQL Server only: option name (SSIS, SSRS, PBIRS, SSAS, TDE) -> its port, if it listens on one, and its option settings by AWS name."
  type = map(object({
    port     = optional(number)
    settings = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = length(var.options) == 0 || startswith(var.engine, "sqlserver-")
    error_message = "Options are for RDS for SQL Server only."
  }

  validation {
    condition     = alltrue([for name in keys(var.options) : contains(["SSIS", "SSRS", "PBIRS", "SSAS", "TDE"], name)])
    error_message = "options are SSIS, SSRS, PBIRS, SSAS and TDE; native backup and restore is backup_restore_bucket."
  }

  validation {
    condition     = length(var.options) == 0 || contains(["sqlserver-se", "sqlserver-ee"], var.engine)
    error_message = "SSIS, SSRS, PBIRS, SSAS and TDE need SQL Server Standard or Enterprise edition."
  }

  validation {
    condition     = length(setintersection(keys(var.options), ["SSIS", "SSRS", "PBIRS", "SSAS"])) == 0 || var.domain != null || var.domain_fqdn != null
    error_message = "SSIS, SSRS, PBIRS and SSAS sign people in through Windows: join the database to Active Directory first."
  }
}

variable "backup_restore_bucket" {
  description = "SQL Server only: the bucket native backups go to and restores come from (SQLSERVER_BACKUP_RESTORE); null = none."
  type        = string
  default     = null

  validation {
    condition     = var.backup_restore_bucket == null || startswith(var.engine, "sqlserver-")
    error_message = "Native backup and restore to S3 is for RDS for SQL Server only; RDS Custom backs up to S3 from the server itself."
  }
}

variable "domain" {
  description = "SQL Server only: an AWS Managed Microsoft AD directory ID to join (d-...), with domain_iam_role_name."
  type        = string
  default     = null

  validation {
    condition     = var.domain == null || startswith(var.engine, "sqlserver-")
    error_message = "domain is for RDS for SQL Server; RDS Custom joins either kind of directory through domain_fqdn and its companions."
  }
}

variable "domain_iam_role_name" {
  description = "The role RDS joins the AWS Managed Microsoft AD directory with."
  type        = string
  default     = null

  validation {
    condition     = (var.domain == null) == (var.domain_iam_role_name == null)
    error_message = "domain and domain_iam_role_name go together."
  }
}

variable "domain_fqdn" {
  description = "SQL Server only: a self-managed Active Directory's domain to join, such as corp.example.com (and RDS Custom's way into any directory)."
  type        = string
  default     = null

  validation {
    condition     = var.domain_fqdn == null || can(regex("sqlserver-", var.engine))
    error_message = "Active Directory is for SQL Server only."
  }

  validation {
    condition     = var.domain == null || var.domain_fqdn == null
    error_message = "Join AWS Managed Microsoft AD (domain) or a self-managed domain (domain_fqdn), not both."
  }
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

  validation {
    condition     = (var.domain_fqdn == null && var.domain_ou == null && var.domain_auth_secret_arn == null && var.domain_dns_ips == null) || (var.domain_fqdn != null && var.domain_ou != null && var.domain_auth_secret_arn != null && length(coalesce(var.domain_dns_ips, [])) == 2)
    error_message = "A self-managed domain needs domain_fqdn, domain_ou, domain_auth_secret_arn and two domain_dns_ips."
  }
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
  description = "RDS Custom only: license-included, or bring-your-own-media for a custom engine version built from our own SQL Server media."
  type        = string
  default     = "license-included"

  validation {
    condition     = var.license_model == "license-included" || (var.license_model == "bring-your-own-media" && contains(["custom-sqlserver-ee", "custom-sqlserver-se", "custom-sqlserver-dev"], var.engine))
    error_message = "license_model is license-included, or bring-your-own-media for RDS Custom Enterprise, Standard or Developer edition."
  }

  validation {
    condition     = var.engine != "custom-sqlserver-dev" || var.license_model == "bring-your-own-media"
    error_message = "Developer edition comes only from our own media: license_model bring-your-own-media, with a custom engine version."
  }
}
