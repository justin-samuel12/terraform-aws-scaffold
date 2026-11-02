variable "name" {
  description = "The group's name: the Auto Scaling group and launch template are <environment>-<name>, and every instance is tagged Group = <name>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens, 23 characters at most."
  }
}

variable "environment" {
  description = "The environment it runs in."
  type        = string
}

variable "image_id" {
  description = "The AMI, pinned by ID. Changing it rolls every instance onto it, a few at a time (instance refresh)."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.image_id))
    error_message = "image_id is an AMI ID (ami-...), never a name or a search."
  }
}

variable "instance_type" {
  description = "The instance type."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups for every instance."
  type        = list(string)
}

variable "instance_profile" {
  description = "The instance profile every instance runs as."
  type        = string
}

variable "kms_key_arn" {
  description = "The environment's data key, for every disk."
  type        = string
}

variable "root_size" {
  description = "Root disk GB."
  type        = number
  default     = 30
}

variable "volumes" {
  description = "Extra disks every instance gets, by name: device, GB, IOPS, throughput. They belong to the instance and go with it."
  type = map(object({
    device     = string
    size       = number
    iops       = optional(number, 3000)
    throughput = optional(number, 125)
  }))
  default = {}
}

variable "user_data" {
  description = "The boot script every instance runs when it starts. Never secrets."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags for every instance and disk."
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "The subnets instances launch into: one per zone of the group's tier."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An Auto Scaling group spreads across at least two zones."
  }
}

variable "min_size" {
  description = "The fewest instances."
  type        = number
}

variable "max_size" {
  description = "The most instances."
  type        = number
}

variable "desired_capacity" {
  description = "How many to start with; scaling changes it from then on, and plans leave it alone."
  type        = number
}

variable "target_group_arns" {
  description = "Target groups every instance joins."
  type        = list(string)
  default     = []
}

variable "target_tracking_configuration" {
  description = "Scale to keep a metric at a value, as aws_autoscaling_policy writes it: predefined_metric_type (ASGAverageCPUUtilization, ASGAverageNetworkIn, ASGAverageNetworkOut, ALBRequestCountPerTarget) and target_value. null: a fixed size."
  type = object({
    predefined_metric_type = string
    target_value           = number
    resource_label         = optional(string)
  })
  default = null

  validation {
    condition     = var.target_tracking_configuration == null || contains(["ASGAverageCPUUtilization", "ASGAverageNetworkIn", "ASGAverageNetworkOut", "ALBRequestCountPerTarget"], try(var.target_tracking_configuration.predefined_metric_type, ""))
    error_message = "predefined_metric_type is ASGAverageCPUUtilization, ASGAverageNetworkIn, ASGAverageNetworkOut or ALBRequestCountPerTarget."
  }
}

variable "backup" {
  description = "Tag instances Backup = standard. Off by default: instances in an Auto Scaling group are replaceable, and their state belongs elsewhere."
  type        = bool
  default     = false
}
