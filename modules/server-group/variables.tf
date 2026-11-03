variable "name" {
  description = "The group's name: its servers are <name>-01 and so on, tagged Group = <name>; it also names its target group and CodeDeploy application."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "The environment it runs in."
  type        = string
}

variable "vpc_id" {
  description = "The environment's VPC, for the target group."
  type        = string
}

variable "servers" {
  description = "Everything the ec2-instance module takes for the group's servers, placement and addresses already resolved."
  type = object({
    members = map(object({
      subnet_id     = string
      subnet        = string
      instance_type = string
      private_ip    = optional(string)
      secondary_ips = optional(list(string), [])
    }))
    image_id           = string
    security_group_ids = list(string)
    instance_profile   = string
    kms_key_arn        = string
    root_size          = optional(number, 30)
    volumes = optional(map(object({
      device     = string
      size       = number
      iops       = optional(number, 3000)
      throughput = optional(number, 125)
    })), {})
    backup    = optional(bool, true)
    user_data = optional(string)
    tags      = optional(map(string), {})
  })
}

variable "port" {
  description = "The port its servers listen on; required when it has routes."
  type        = number
  default     = null
}

variable "health" {
  description = "The path the load balancer checks."
  type        = string
  default     = "/"
}

variable "target" {
  description = "How its own target group talks to it: protocol (HTTP or HTTPS), the health check's healthy codes, sticky sessions in seconds (null: none), and slow start in seconds (0: none)."
  type = object({
    protocol   = optional(string, "HTTP")
    matcher    = optional(string, "200-399")
    stickiness = optional(number)
    slow_start = optional(number, 0)
  })
  default = {}

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target.protocol) && (var.target.slow_start == 0 || (var.target.slow_start >= 30 && var.target.slow_start <= 900)) && (var.target.stickiness == null || (coalesce(var.target.stickiness, 1) >= 1 && coalesce(var.target.stickiness, 1) <= 604800))
    error_message = "target: protocol HTTP or HTTPS; slow_start 0 or 30 to 900 seconds; stickiness 1 to 604800 seconds."
  }
}

variable "targets" {
  description = "A network load balancer's target groups (from the load-balancers stack) its servers also join: name -> the group's ARN and name, and the port."
  type = map(object({
    arn  = string
    name = string
    port = number
  }))
  default = {}
}

variable "routes" {
  description = "Where traffic reaches it: a shared listener (by ARN) and the hosts and paths it owns there, at a priority unique on that listener."
  type = list(object({
    listener_arn = string
    hosts        = optional(list(string), [])
    paths        = optional(list(string), [])
    priority     = number
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.routes : length(r.hosts) + length(r.paths) > 0 && r.priority >= 1000 && r.priority <= 50000])
    error_message = "A route matches at least one host or path, with a priority from 1000 to 50000 (1 to 999 belong to the load balancer's own rules, so the two stacks never clash)."
  }
}

variable "names" {
  description = "DNS names for it: each an alias to a load balancer, in a zone."
  type = list(object({
    zone_id     = string
    name        = string
    lb_dns_name = string
    lb_zone_id  = string
  }))
  default = []
}

variable "autoscaling" {
  description = "Run the group as an Auto Scaling group instead of fixed servers: the subnets to launch into, min_size, max_size, desired_capacity and an optional target_tracking_configuration. null: fixed servers, from servers.members."
  type = object({
    subnet_ids       = list(string)
    min_size         = number
    max_size         = number
    desired_capacity = number
    target_tracking_configuration = optional(object({
      predefined_metric_type = string
      target_value           = number
      resource_label         = optional(string)
    }))
  })
  default = null
}

variable "instance_type" {
  description = "The instance type for an Auto Scaling group (fixed servers take theirs from servers.members)."
  type        = string
  default     = null
}
