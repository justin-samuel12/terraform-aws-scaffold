variable "cluster_name" {
  description = "The cluster the apps run in."
  type        = string
}

variable "cluster_arn" {
  description = "The cluster's ARN; only Pod Identity acting for this cluster may assume the roles."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:eks:[a-z0-9-]+:[0-9]{12}:cluster/.+$", var.cluster_arn))
    error_message = "cluster_arn is an EKS cluster's ARN."
  }
}

variable "roles" {
  description = "Role name -> what it is for, the namespace and service account whose pods get it, the ARNs of the policies attached to it (policy_arns), and statements only it needs. One role per app, so Vault's AWS auth tells apps apart."
  type = map(object({
    description     = string
    namespace       = string
    service_account = string
    policy_arns     = optional(list(string), [])
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
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.roles) : can(regex("^[a-z][a-z0-9-]{0,63}$", name))])
    error_message = "Role names are lowercase letters, digits and hyphens, 64 characters at most."
  }

  validation {
    condition     = alltrue([for r in var.roles : can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", r.namespace)) && can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", r.service_account))])
    error_message = "namespace and service_account are Kubernetes names: lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = length(distinct([for r in values(var.roles) : "${r.namespace}/${r.service_account}"])) == length(var.roles)
    error_message = "Each role has its own namespace and service account; two roles cannot share one."
  }

  validation {
    condition = alltrue(flatten([for r in var.roles : [
      for s in r.statements : !(contains(s.actions, "*") && contains(s.resources, "*")) && contains(["Allow", "Deny"], s.effect)
    ]]))
    error_message = "No statement may allow every action on every resource; scope actions and resources (SKILLS.md)."
  }

  validation {
    condition     = alltrue(flatten([for r in var.roles : [for p in r.policy_arns : can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/.+$", p)) && !contains(["AdministratorAccess", "PowerUserAccess", "IAMFullAccess"], element(split("/", p), length(split("/", p)) - 1))]]))
    error_message = "policy_arns are policy ARNs, and an app's role never takes AdministratorAccess, PowerUserAccess or IAMFullAccess; give it statements for what it actually does."
  }

  validation {
    condition     = alltrue([for r in var.roles : trimspace(r.description) != ""])
    error_message = "Every role needs a description."
  }
}
