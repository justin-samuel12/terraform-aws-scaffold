variable "policies" {
  description = "Customer-managed policy name -> what it is for and its statements; several roles can share one."
  type = map(object({
    description = string
    statements = list(object({
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
      condition = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.policies) : can(regex("^[a-z][a-z0-9-]{0,127}$", name))])
    error_message = "Policy names are lowercase letters, digits and hyphens."
  }

  validation {
    condition = alltrue(flatten([for p in var.policies : concat([trimspace(p.description) != "" && length(p.statements) > 0], [
      for s in p.statements : !(contains(s.actions, "*") && contains(s.resources, "*")) && contains(["Allow", "Deny"], s.effect)
    ])]))
    error_message = "Every policy needs a description and statements, and none may allow every action on every resource (SKILLS.md)."
  }
}

variable "roles" {
  description = "Role name -> what it is for, which AWS services may assume it (or its whole trust policy, as JSON, in assume_role_policy), AWS managed policies by name, our own policies by name, and statements only it needs."
  type = map(object({
    description        = string
    services           = optional(set(string), [])
    assume_role_policy = optional(string)
    managed_policies   = optional(list(string), [])
    policies           = optional(list(string), [])
    policy_arns        = optional(list(string), [])
    statements = optional(list(object({
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
      condition = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  }))

  validation {
    condition     = alltrue([for name in keys(var.roles) : can(regex("^[a-z][a-z0-9-]{0,63}$", name))])
    error_message = "Role names are lowercase letters, digits and hyphens."
  }

  validation {
    condition     = alltrue([for r in var.roles : (length(r.services) > 0) != (r.assume_role_policy != null) && alltrue([for s in r.services : can(regex("^[a-z0-9.-]+$", s))])])
    error_message = "Every role is assumed by at least one AWS service, named without .amazonaws.com (ec2, lambda), or has an assume_role_policy, never both."
  }

  validation {
    condition = alltrue(flatten([for r in var.roles : [
      for s in r.statements : !(contains(s.actions, "*") && contains(s.resources, "*")) && contains(["Allow", "Deny"], s.effect)
    ]]))
    error_message = "No statement may allow every action on every resource; scope actions and resources (SKILLS.md)."
  }

  validation {
    condition     = alltrue([for r in var.roles : trimspace(r.description) != ""])
    error_message = "Every role needs a description."
  }

  validation {
    condition     = alltrue(flatten([for r in var.roles : [for p in r.policies : contains(keys(var.policies), p)]]))
    error_message = "A role's policies must be policies defined here (policies/<name>.yml); AWS's own go under managed_policies."
  }
}

variable "instance_profiles" {
  description = "Instance profile name -> the role it holds; null gives every role EC2 assumes a profile of its own name."
  type        = map(string)
  default     = null

  validation {
    condition     = var.instance_profiles == null || alltrue([for name, role in coalesce(var.instance_profiles, {}) : can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", name)) && contains(keys(var.roles), role)])
    error_message = "An instance profile's name is up to 128 letters, digits and +=,.@_-, and its role is one of the roles here."
  }
}
