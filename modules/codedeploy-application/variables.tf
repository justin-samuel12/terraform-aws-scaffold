variable "name" {
  description = "The application's name, the same in every environment, as servers declare it in their CodeDeploy tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{0,99}$", var.name))
    error_message = "name is lowercase letters, digits, dots, hyphens and underscores."
  }
}

variable "environment" {
  description = "The environment these deployment groups deploy to; servers are found by its Environment tag."
  type        = string
}

variable "region" {
  description = "The region the application is in, for the ownership check of a shared application."
  type        = string
}

variable "account_id" {
  description = "The account the application is in, for the ownership check of a shared application."
  type        = string
}

variable "containerized" {
  description = "Every server running it is containerized (isContainerized = true): one application shared by the environments, owned by the first to create it, and one deployment group per environment, primary-<environment>. Otherwise it gets the groups in var.groups."
  type        = bool
  default     = false
}

variable "groups" {
  description = "The deployment groups an application gets, one per branch deployed from. A containerized one gets primary-<environment> instead."
  type        = list(string)
  default     = ["master", "development", "adhoc"]

  validation {
    condition     = length(var.groups) > 0 && alltrue([for g in var.groups : can(regex("^[a-z0-9][a-z0-9._-]*$", g))])
    error_message = "groups lists at least one deployment group name: lowercase letters, digits, dots, hyphens, underscores."
  }
}

variable "deployment_config_name" {
  description = "How a deployment rolls out across servers: CodeDeployDefault.OneAtATime, CodeDeployDefault.HalfAtATime, CodeDeployDefault.AllAtOnce, or a custom configuration."
  type        = string
  default     = "CodeDeployDefault.OneAtATime"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.deployment_config_name))
    error_message = "deployment_config_name is a CodeDeploy deployment configuration's name, such as CodeDeployDefault.OneAtATime."
  }
}

variable "rollback_events" {
  description = "When a deployment rolls back by itself: DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM, DEPLOYMENT_STOP_ON_REQUEST. Empty: never."
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE"]

  validation {
    condition     = alltrue([for e in var.rollback_events : contains(["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"], e)])
    error_message = "rollback_events are DEPLOYMENT_FAILURE, DEPLOYMENT_STOP_ON_ALARM or DEPLOYMENT_STOP_ON_REQUEST."
  }
}

variable "selector" {
  description = "A third tag the servers must carry, from the CodeDeploy tag's '<application>:Key=Value' form; null for none."
  type = object({
    key   = string
    value = string
  })
  default = null
}

variable "autoscaling_groups" {
  description = "Auto Scaling groups running it: deployed to by name, so new instances get the current release as they launch."
  type        = list(string)
  default     = []
}

variable "target_group_names" {
  description = "Target groups its servers are in. With more than one server behind them, deployments drain each server from them first."
  type        = list(string)
  default     = []
}

variable "servers_behind_load_balancer" {
  description = "How many of its servers are in those target groups (an Auto Scaling group counts as several); traffic control needs at least two."
  type        = number
  default     = 0
}

variable "service_role_arn" {
  description = "The environment's CodeDeploy service role."
  type        = string
}

variable "bootstrap" {
  description = "A GitHub revision deployed once, to a group of its own with no servers, then stopped, so CodeDeploy's GitHub connection exists before the first real deployment; null for none."
  type = object({
    repository = string
    commit_id  = string
  })
  default = null
}
