variable "environment" {
  description = "The environment whose pipeline roles these are: terraform-plan-<environment>, terraform-propose-<environment> and one terraform-apply-<environment>-<duty> per duty."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment is lowercase letters, digits and hyphens."
  }
}

variable "account_id" {
  description = "The environment's account, the one this stack runs in."
  type        = string
}

variable "hub_account_id" {
  description = "The account of the hub's Transit Gateway and shared zones."
  type        = string
}

variable "github_repository" {
  description = "The GitHub repository, owner/name, whose workflows may assume the roles."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository is owner/name, such as example-org/infrastructure."
  }
}

variable "branch" {
  description = "The protected branch. Plans are proposed only from it; pull requests into it plan read-only."
  type        = string
}

variable "create_oidc_provider" {
  description = "true: this stack creates the account's GitHub OIDC provider. false: another stack in the same account already did, and it is looked up."
  type        = bool
}

variable "state_bucket" {
  description = "The Terraform state bucket."
  type        = string
}

variable "state_key_format" {
  description = "state.key from config/global.yml."
  type        = string
  default     = "{region}/{environment}/{component}"
}

variable "duties" {
  description = "The duties this environment deploys, from templates/duties.yml: one apply role and one permission boundary each."
  type = map(object({
    components = list(string)
    actions    = list(string)
    uses       = list(string)
    roles      = optional(list(string), [])
    across     = optional(list(string), [])
  }))
}

variable "other_environments" {
  description = "Every other environment's name, whose buckets this environment's roles are refused."
  type        = list(string)
  default     = []
}

variable "hub_segments" {
  description = "Region -> this environment's segment and the segments it announces to, for its terraform-network-<environment> role in the hub. Empty for shared."
  type = map(object({
    segment       = string
    propagates_to = list(string)
  }))
  default = {}
}

variable "spokes" {
  description = "Only in the hub's account: environment -> its account and its hub segments, one terraform-network-<environment> role each, the only way its network stacks change the hub."
  type = map(object({
    account_id   = string
    hub_segments = map(object({ segment = string, propagates_to = list(string) }))
  }))
  default = {}
}
