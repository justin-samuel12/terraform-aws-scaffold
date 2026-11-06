variable "environment" {
  description = "The environment: its patch group, and part of every server's tags."
  type        = string
}

variable "group" {
  description = "The group's name; its servers are <group>-01, <group>-02, ..."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,40}$", var.group))
    error_message = "group is lowercase letters, digits and hyphens."
  }
}

variable "members" {
  description = "Server name -> its subnet (id and Subnet tag), its instance type, its chosen primary and secondary addresses, if any, and tags of its own."
  type = map(object({
    subnet_id     = string
    subnet        = string
    instance_type = string
    private_ip    = optional(string)
    secondary_ips = optional(list(string), [])
    tags          = optional(map(string), {})
  }))
}

variable "image_id" {
  description = "The image every server is built from, pinned: a new image is rolled out by changing this, deliberately."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.image_id))
    error_message = "image_id is an AMI id, such as ami-0123456789abcdef0, never a name or a search."
  }
}

variable "security_group_ids" {
  description = "The servers' security groups."
  type        = list(string)
}

variable "instance_profile" {
  description = "The instance profile (an iam stack role EC2 assumes), or null."
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "The environment's data key, for every disk."
  type        = string
}

variable "root_size" {
  description = "Root disk size in GB."
  type        = number
  default     = 30
}

variable "volumes" {
  description = "Extra disks per server: key -> device, size in GB, and an optional name, IOPS, throughput and tags."
  type = map(object({
    device     = string
    size       = number
    name       = optional(string)
    iops       = optional(number, 3000)
    throughput = optional(number, 125)
    tags       = optional(map(string), {})
  }))
  default = {}
}

variable "backup" {
  description = "Back the servers up with the environment's AWS Backup plan."
  type        = bool
  default     = true
}

variable "user_data" {
  description = "A boot script. Never secrets: user data is readable by anyone who can describe the instance."
  type        = string
  default     = null
}

variable "target_groups" {
  description = "Target group name -> its ARN and the port every server is registered on. Keyed by name, which is known before the target group exists."
  type = map(object({
    arn  = string
    port = number
  }))
  default = {}
}

variable "tags" {
  description = "Extra tags on every server."
  type        = map(string)
  default     = {}
}
