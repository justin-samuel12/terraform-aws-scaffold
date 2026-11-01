variable "vpc_id" {
  description = "The VPC the endpoints are created in."
  type        = string
}

variable "vpc_cidr" {
  description = "The VPC's range: the only addresses allowed to reach the interface endpoints."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be an IPv4 CIDR."
  }
}

variable "interface" {
  description = "Services reached through interface endpoints in subnet_ids, such as ssm, ssmmessages, ec2messages, logs, kms."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.interface : can(regex("^[a-z0-9][a-z0-9.-]*$", s))])
    error_message = "Interface services are AWS service names without the com.amazonaws.<region>. prefix, such as ssm."
  }
}

variable "gateway" {
  description = "Services reached through gateway endpoints on route_table_ids: s3, dynamodb."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.gateway : contains(["s3", "dynamodb"], s)])
    error_message = "Only s3 and dynamodb have gateway endpoints."
  }
}

variable "subnet_ids" {
  description = "One subnet per zone for the interface endpoints' network interfaces."
  type        = list(string)
  default     = []
}

variable "route_table_ids" {
  description = "Every route table in the VPC, so each tier, data included, reaches the gateway services."
  type        = list(string)
  default     = []
}
