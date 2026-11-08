variable "environment" {
  description = "The environment the policies are for: shared for the hub, or a spoke such as staging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment is lowercase letters, digits and hyphens."
  }
}

variable "partition" {
  description = "The AWS partition the ARNs are in."
  type        = string
  default     = "aws"
}

variable "account_id" {
  description = "The environment's AWS account: the one its roles, boundary and resources live in."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id is 12 digits."
  }
}

variable "hub_account_id" {
  description = "The account of the hub's Transit Gateway and shared zones: the one terraform-network-<environment> lives in."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.hub_account_id))
    error_message = "hub_account_id is 12 digits."
  }
}

variable "state_bucket" {
  description = "The Terraform state bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "state_bucket is an S3 bucket name."
  }
}

variable "state_key_format" {
  description = "state.key from config/global.yml: how a stack's state key is built from {region}, {environment}, {component} and {account_id}."
  type        = string
  default     = "{region}/{environment}/{component}"

  validation {
    condition     = strcontains(var.state_key_format, "{environment}") && strcontains(var.state_key_format, "{component}")
    error_message = "state_key_format contains {environment} and {component}, or two stacks could share a state."
  }
}

variable "duties" {
  description = "The duties this environment deploys, from templates/duties.yml: each one's components, the actions it may take, and the actions it may take on resources another duty owns."
  type = map(object({
    components = list(string)
    actions    = list(string)
    uses       = list(string)
    roles      = optional(list(string), [])
    across     = optional(list(string), [])
  }))

  validation {
    condition     = alltrue([for name, d in var.duties : can(regex("^[a-z][a-z0-9-]*$", name)) && length(d.components) > 0])
    error_message = "Each duty has a lowercase name and at least one component."
  }

  validation {
    condition     = length(distinct(flatten([for d in values(var.duties) : d.components]))) == length(flatten([for d in values(var.duties) : d.components]))
    error_message = "A component belongs to one duty only, or two roles could write the same state."
  }
}

variable "other_environments" {
  description = "Every other environment's name: a bucket is named after its environment, so a role made here is refused their buckets by name, which tags cannot do for S3."
  type        = list(string)
  default     = []
}

variable "hub_segments" {
  description = "Region -> the environment's network there: the hub route table it joins (segment) and those it announces its routes to (propagates_to). Empty for shared, or where a parent organization runs the Transit Gateway."
  type = map(object({
    segment       = string
    propagates_to = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.hub_segments) : contains(["restricted", "standard", "shared"], r.segment) && alltrue([for s in r.propagates_to : contains(["restricted", "standard", "shared"], s)])])
    error_message = "Segments are restricted, standard or shared."
  }
}

variable "github_repository" {
  description = "The GitHub repository, owner/name, whose workflows may assume the pipeline's roles."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository is owner/name, such as example-org/infrastructure."
  }
}

variable "branch" {
  description = "The protected branch: plans are proposed only from it."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.branch))
    error_message = "branch is a git branch name."
  }
}

variable "github_oidc_host" {
  description = "The GitHub OIDC issuer host, whose provider in IAM the pipeline's roles trust."
  type        = string
  default     = "token.actions.githubusercontent.com"
}
