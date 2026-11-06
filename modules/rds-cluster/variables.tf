variable "name" {
  description = "The cluster's identifier; its instances are <name>-1, <name>-2 and so on."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,59}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens, starting with a letter, 60 characters at most."
  }
}

variable "engine" {
  description = "aurora-postgresql or aurora-mysql."
  type        = string

  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "engine must be aurora-postgresql or aurora-mysql."
  }
}

variable "engine_version" {
  description = "Such as 16.6 for aurora-postgresql or 8.0.mysql_aurora.3.08.0 for aurora-mysql; minor versions upgrade themselves in the maintenance window."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?(\\.mysql_aurora\\.[0-9.]+)?$", var.engine_version))
    error_message = "engine_version is a version such as 16.6 or 8.0.mysql_aurora.3.08.0."
  }
}

variable "instance_class" {
  description = "Such as db.r6g.large, or db.serverless for Aurora Serverless v2."
  type        = string
}

variable "instances" {
  description = "How many aws_rds_cluster_instance: the first, <name>-1, is the writer, the others readers in other zones that take over by themselves."
  type        = number

  validation {
    condition     = var.instances >= 1 && var.instances <= 15 && floor(var.instances) == var.instances
    error_message = "instances is a whole number from 1 to 15."
  }
}

variable "serverlessv2_scaling_configuration" {
  description = "Serverless v2 only (instance_class db.serverless): min_capacity and max_capacity, in Aurora capacity units (ACUs), for each instance."
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = null

  validation {
    condition     = (var.instance_class == "db.serverless") == (var.serverlessv2_scaling_configuration != null)
    error_message = "Serverless v2 (instance_class db.serverless) needs serverlessv2_scaling_configuration, and only it takes one."
  }
}

variable "subnet_ids" {
  description = "The data tier's subnets, one per zone."
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "The cluster's security groups, by ID."
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

variable "tags" {
  description = "Tags from the file, on everything this module builds; the ones it sets itself (Name and the like) win."
  type        = map(string)
  default     = {}
}
