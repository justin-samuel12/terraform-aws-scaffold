variable "name" {
  description = "The load balancer's name; target groups are named from it. 28 characters at most, so target group names fit AWS's 32."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens, 32 characters at most (AWS's limit): <environment>-<load balancer>."
  }
}

variable "type" {
  description = "application (HTTP and HTTPS) or network (TCP, UDP and TLS)."
  type        = string

  validation {
    condition     = contains(["application", "network"], var.type)
    error_message = "type must be application or network."
  }
}

variable "internal" {
  description = "true for a load balancer reached only from inside our networks; false for internet-facing."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "The VPC its target groups belong to."
  type        = string
}

variable "subnet_ids" {
  description = "One subnet per zone: the private tier for internal, the public tier for internet-facing."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A load balancer needs a subnet in at least two zones."
  }
}

variable "security_group_ids" {
  description = "The security groups on the load balancer."
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "The ACM certificate for HTTPS and TLS listeners."
  type        = string
  default     = null
}

variable "targets" {
  description = "Target group name -> where it sends traffic and how health is checked."
  type = map(object({
    port              = number
    protocol          = string
    health_check_path = optional(string)
  }))

  validation {
    condition     = alltrue([for name in keys(var.targets) : can(regex("^[a-z][a-z0-9-]*$", name)) && length(name) <= 32])
    error_message = "Target names are lowercase with hyphens, and <load balancer>-<target> must fit in 27 characters (AWS allows 32; five go to the suffix that lets a group be rebuilt in place)."
  }

  validation {
    condition     = alltrue([for t in var.targets : t.port >= 1 && t.port <= 65535 && contains(["HTTP", "HTTPS", "TCP", "UDP", "TCP_UDP", "TLS"], t.protocol)])
    error_message = "A target's port is 1 to 65535, and its protocol HTTP, HTTPS, TCP, UDP, TCP_UDP or TLS."
  }
}

variable "listeners" {
  description = "Listening port -> protocol and the target it forwards to. On an application load balancer, port 80 with redirect = true sends everything to HTTPS, and a listener with no target answers 404 to whatever no rule or application route claims."
  type = map(object({
    protocol = string
    target   = optional(string)
    redirect = optional(bool, false)
  }))

  validation {
    condition     = alltrue([for l in var.listeners : l.redirect ? l.target == null : l.target == null || contains(keys(var.targets), coalesce(l.target, "-"))])
    error_message = "A listener forwards to one of this load balancer's targets, is a redirect with no target, or has no target and answers 404."
  }

  validation {
    condition     = var.type == "application" || alltrue([for l in var.listeners : l.target != null])
    error_message = "A network load balancer's listener has no rules and no fixed response: it forwards to a target."
  }

  validation {
    condition = alltrue([
      for l in var.listeners : var.type == "application" ? contains(["HTTP", "HTTPS"], l.protocol) : contains(["TCP", "UDP", "TCP_UDP", "TLS"], l.protocol)
    ])
    error_message = "An application load balancer listens on HTTP or HTTPS; a network load balancer on TCP, UDP, TCP_UDP or TLS."
  }

  validation {
    condition     = alltrue([for l in var.listeners : !contains(["HTTPS", "TLS"], l.protocol) || var.certificate_arn != null])
    error_message = "HTTPS and TLS listeners need certificate_arn."
  }

  validation {
    condition     = alltrue([for l in var.listeners : var.internal || l.protocol != "HTTP" || l.redirect])
    error_message = "An internet-facing load balancer serves nothing over plain HTTP: an HTTP listener there must be a redirect to HTTPS."
  }
}

variable "access_logs_bucket" {
  description = "The region's load balancer log bucket (the logging stack's); every request is logged there."
  type        = string
}

variable "rules" {
  description = "Rule name -> the listener port it belongs to, its priority, the hosts and paths it matches, and one action: forward to a target, redirect, or a fixed response."
  type = map(object({
    listener = string
    priority = number
    hosts    = optional(list(string), [])
    paths    = optional(list(string), [])
    target   = optional(string)
    redirect = optional(object({
      host        = optional(string, "#{host}")
      path        = optional(string, "/#{path}")
      query       = optional(string, "#{query}")
      status_code = optional(string, "HTTP_301")
    }))
    fixed_response = optional(object({
      status_code  = string
      content_type = optional(string, "text/plain")
      body         = optional(string, "")
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for r in var.rules : contains(keys(var.listeners), r.listener)])
    error_message = "A rule's listener must be one of this load balancer's listener ports."
  }

  validation {
    condition     = alltrue([for r in var.rules : length(compact([r.target, r.redirect == null ? null : "redirect", r.fixed_response == null ? null : "fixed"])) == 1])
    error_message = "A rule has exactly one action: target, redirect or fixed_response."
  }

  validation {
    condition     = alltrue([for r in var.rules : r.target == null || contains(keys(var.targets), coalesce(r.target, "-"))])
    error_message = "A rule's target must be one of this load balancer's targets."
  }

  validation {
    condition     = alltrue([for r in var.rules : length(r.hosts) + length(r.paths) > 0 && r.priority >= 1 && r.priority <= 999])
    error_message = "A rule matches at least one host or path, with a priority from 1 to 999 (1000 and up belong to applications' routes, so the two stacks never clash)."
  }

  validation {
    condition     = length(distinct([for r in var.rules : "${r.listener}/${r.priority}"])) == length(var.rules)
    error_message = "Two rules on one listener cannot share a priority."
  }
}
