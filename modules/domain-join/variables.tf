variable "environment" {
  description = "The environment whose Windows servers join: names the document (<environment>-DomainJoin) and the join secret (domain-join/<environment>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "associations" {
  description = "Association name -> the aws_ssm_association arguments: targets (the servers, by tag), parameters (DomainName, OrganizationalUnit), schedule_expression, compliance_severity, max_concurrency, max_errors. Nothing is built without one."
  type = map(object({
    targets = list(object({
      key    = string
      values = list(string)
    }))
    parameters          = map(string)
    schedule_expression = optional(string)
    compliance_severity = optional(string)
    max_concurrency     = optional(string)
    max_errors          = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, a in var.associations : can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", try(a.parameters.DomainName, ""))) && can(regex("^(OU|CN)=[^'{}]+,DC=[^'{}]+$", try(a.parameters.OrganizationalUnit, ""))) && length(setsubtract(keys(a.parameters), ["DomainName", "OrganizationalUnit"])) == 0])
    error_message = "Each association's parameters are DomainName (the domain's DNS name) and OrganizationalUnit (the OU's distinguished name, OU=...,DC=...), and nothing else: SecretId is the environment's join secret."
  }

  validation {
    condition     = alltrue([for name, a in var.associations : length(a.targets) > 0 && alltrue([for t in a.targets : startswith(t.key, "tag:") && length(t.values) > 0])])
    error_message = "Each association targets servers by tag (key: tag:Domain), never every instance."
  }
}
