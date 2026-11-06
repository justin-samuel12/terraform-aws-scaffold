variable "vpc_id" {
  description = "The VPC the endpoints are created in."
  type        = string
}

variable "endpoints" {
  description = "Endpoint name -> the arguments of aws_vpc_endpoint: service_name in full (com.amazonaws.<region>.<service>), vpc_endpoint_type, and for an Interface endpoint subnet_ids, security_group_ids and private_dns_enabled, for a Gateway endpoint route_table_ids; tags."
  type = map(object({
    service_name        = string
    vpc_endpoint_type   = string
    subnet_ids          = optional(list(string), [])
    security_group_ids  = optional(list(string), [])
    private_dns_enabled = optional(bool)
    route_table_ids     = optional(list(string), [])
    tags                = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for e in var.endpoints : contains(["Interface", "Gateway"], e.vpc_endpoint_type) && can(regex("^com\\.amazonaws\\.[a-z]{2}-[a-z]+-[0-9]\\.[a-z0-9][a-z0-9.-]*$", e.service_name))])
    error_message = "vpc_endpoint_type is Interface or Gateway, and service_name an AWS service's full name, such as com.amazonaws.us-east-2.ssm."
  }

  validation {
    condition     = alltrue([for e in var.endpoints : e.vpc_endpoint_type != "Interface" || length(e.subnet_ids) >= 2 && length(e.security_group_ids) > 0])
    error_message = "An Interface endpoint needs a subnet in at least two zones and a security group."
  }

  validation {
    condition     = alltrue([for e in var.endpoints : e.vpc_endpoint_type != "Gateway" || length(e.route_table_ids) > 0])
    error_message = "A Gateway endpoint needs route tables."
  }
}
