variable "name" {
  description = "The load balancer's name; target groups are named from it. 28 characters at most, so target group names fit AWS's 32."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens, 32 characters at most (AWS's limit): <environment>-<load balancer>."
  }
}

variable "load_balancer_type" {
  description = "application (HTTP and HTTPS) or network (TCP, UDP and TLS)."
  type        = string

  validation {
    condition     = contains(["application", "network"], var.load_balancer_type)
    error_message = "load_balancer_type must be application or network."
  }
}

variable "internal" {
  description = "true for a load balancer reached only from inside our networks; false for internet-facing."
  type        = bool
}

variable "vpc_id" {
  description = "The VPC its target groups belong to."
  type        = string
}

variable "subnets" {
  description = "Subnet IDs, one per zone."
  type        = list(string)

  validation {
    condition     = length(var.subnets) >= 2
    error_message = "A load balancer needs a subnet in at least two zones."
  }
}

variable "security_groups" {
  description = "Security group IDs on the load balancer."
  type        = list(string)
  default     = []
}

variable "access_logs_bucket" {
  description = "The region's load balancer log bucket (the logging stack's); every request is logged there."
  type        = string
}

variable "target_groups" {
  description = "Target group name -> its aws_lb_target_group arguments. The name is <load balancer>-<name> in its Name tag."
  type = map(object({
    port                 = number
    protocol             = string
    target_type          = string
    deregistration_delay = number
    health_check = optional(object({
      enabled             = optional(bool)
      path                = optional(string)
      port                = optional(string)
      protocol            = optional(string)
      matcher             = optional(string)
      interval            = optional(number)
      timeout             = optional(number)
      healthy_threshold   = optional(number)
      unhealthy_threshold = optional(number)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.target_groups) : can(regex("^[a-z][a-z0-9-]*$", name)) && length(name) <= 32])
    error_message = "Target group names are lowercase with hyphens, and <load balancer>-<target group> must fit in 27 characters (AWS allows 32; five go to the suffix that lets a group be rebuilt in place)."
  }

  validation {
    condition     = alltrue([for t in var.target_groups : t.port >= 1 && t.port <= 65535 && contains(["HTTP", "HTTPS", "TCP", "UDP", "TCP_UDP", "TLS"], t.protocol)])
    error_message = "A target group's port is 1 to 65535, and its protocol HTTP, HTTPS, TCP, UDP, TCP_UDP or TLS."
  }

  validation {
    condition     = alltrue([for t in var.target_groups : contains(["instance", "ip"], t.target_type) && t.deregistration_delay >= 0 && t.deregistration_delay <= 3600])
    error_message = "target_type is instance or ip, and deregistration_delay 0 to 3600 seconds."
  }
}

variable "listeners" {
  description = "aws_lb_listener arguments, one per port: port, protocol, certificate_arn (HTTPS and TLS) and default_action. An action's target_group_arn names a target group of this load balancer, or is an ARN."
  type = list(object({
    port            = number
    protocol        = string
    certificate_arn = optional(string)
    default_action = object({
      type             = string
      target_group_arn = optional(string)
      redirect = optional(object({
        host        = optional(string)
        path        = optional(string)
        port        = optional(string)
        protocol    = optional(string)
        query       = optional(string)
        status_code = string
      }))
      fixed_response = optional(object({
        content_type = string
        message_body = optional(string)
        status_code  = optional(string)
      }))
    })
  }))

  validation {
    condition     = length(distinct([for l in var.listeners : l.port])) == length(var.listeners) && alltrue([for l in var.listeners : l.port >= 1 && l.port <= 65535])
    error_message = "Each listener has its own port, 1 to 65535."
  }

  validation {
    condition = alltrue([
      for l in var.listeners : var.load_balancer_type == "application" ? contains(["HTTP", "HTTPS"], l.protocol) : contains(["TCP", "UDP", "TCP_UDP", "TLS"], l.protocol)
    ])
    error_message = "An application load balancer listens on HTTP or HTTPS; a network load balancer on TCP, UDP, TCP_UDP or TLS."
  }

  validation {
    condition     = alltrue([for l in var.listeners : contains(["HTTPS", "TLS"], l.protocol) == (l.certificate_arn != null)])
    error_message = "HTTPS and TLS listeners need certificate_arn, and no other listener takes one."
  }

  validation {
    condition = alltrue([
      for l in var.listeners : contains(["forward", "redirect", "fixed-response"], l.default_action.type)
      && (l.default_action.type == "forward") == (l.default_action.target_group_arn != null)
      && (l.default_action.type == "redirect") == (l.default_action.redirect != null)
      && (l.default_action.type == "fixed-response") == (l.default_action.fixed_response != null)
    ])
    error_message = "A default_action's type is forward (with target_group_arn), redirect (with redirect) or fixed-response (with fixed_response), and it has only that one."
  }

  validation {
    condition     = alltrue([for l in var.listeners : l.default_action.target_group_arn == null || contains(keys(var.target_groups), coalesce(l.default_action.target_group_arn, "-")) || startswith(coalesce(l.default_action.target_group_arn, "-"), "arn:")])
    error_message = "target_group_arn names one of this load balancer's target groups, or is an ARN."
  }

  validation {
    condition     = var.load_balancer_type == "application" || alltrue([for l in var.listeners : l.default_action.type == "forward"])
    error_message = "A network load balancer's listener has no rules and no fixed response: it forwards to a target group."
  }

  validation {
    condition     = alltrue([for l in var.listeners : var.internal || l.protocol != "HTTP" || (l.default_action.type == "redirect" && try(l.default_action.redirect.protocol, "") == "HTTPS")])
    error_message = "An internet-facing load balancer serves nothing over plain HTTP: an HTTP listener there redirects to protocol HTTPS."
  }
}

variable "listener_rules" {
  description = "Rule name -> its aws_lb_listener_rule arguments: listener_arn (a listener port of this load balancer, or an ARN), priority, one action and its condition (host_header and/or path_pattern values)."
  type = map(object({
    listener_arn = string
    priority     = number
    action = object({
      type             = string
      target_group_arn = optional(string)
      redirect = optional(object({
        host        = optional(string)
        path        = optional(string)
        port        = optional(string)
        protocol    = optional(string)
        query       = optional(string)
        status_code = string
      }))
      fixed_response = optional(object({
        content_type = string
        message_body = optional(string)
        status_code  = optional(string)
      }))
    })
    condition = object({
      host_header = optional(object({
        values = list(string)
      }))
      path_pattern = optional(object({
        values = list(string)
      }))
    })
  }))
  default = {}

  validation {
    condition     = alltrue([for r in var.listener_rules : contains([for l in var.listeners : tostring(l.port)], r.listener_arn) || startswith(r.listener_arn, "arn:")])
    error_message = "A rule's listener_arn is one of this load balancer's listener ports, or an ARN."
  }

  validation {
    condition = alltrue([
      for r in var.listener_rules : contains(["forward", "redirect", "fixed-response"], r.action.type)
      && (r.action.type == "forward") == (r.action.target_group_arn != null)
      && (r.action.type == "redirect") == (r.action.redirect != null)
      && (r.action.type == "fixed-response") == (r.action.fixed_response != null)
    ])
    error_message = "A rule's action type is forward (with target_group_arn), redirect (with redirect) or fixed-response (with fixed_response), and it has only that one."
  }

  validation {
    condition     = alltrue([for r in var.listener_rules : r.action.target_group_arn == null || contains(keys(var.target_groups), coalesce(r.action.target_group_arn, "-")) || startswith(coalesce(r.action.target_group_arn, "-"), "arn:")])
    error_message = "target_group_arn names one of this load balancer's target groups, or is an ARN."
  }

  validation {
    condition     = alltrue([for r in var.listener_rules : length(concat(try(r.condition.host_header.values, []), try(r.condition.path_pattern.values, []))) > 0 && r.priority >= 1 && r.priority <= 999])
    error_message = "A rule matches at least one host or path, with a priority from 1 to 999 (1000 and up belong to applications' rules, so the two stacks never clash)."
  }

  validation {
    condition     = length(distinct([for r in var.listener_rules : "${r.listener_arn}/${r.priority}"])) == length(var.listener_rules)
    error_message = "Two rules on one listener cannot share a priority."
  }
}

variable "listener_certificates" {
  description = "Key -> aws_lb_listener_certificate arguments: listener_arn (an HTTPS or TLS listener port of this load balancer) and the certificate_arn served on it to the names it covers (SNI), beside the listener's own."
  type = map(object({
    listener_arn    = string
    certificate_arn = string
  }))
  default = {}

  validation {
    condition     = alltrue([for c in var.listener_certificates : contains([for l in var.listeners : tostring(l.port) if contains(["HTTPS", "TLS"], l.protocol)], c.listener_arn)])
    error_message = "A listener certificate's listener_arn is one of this load balancer's HTTPS or TLS listener ports."
  }
}
