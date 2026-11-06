variable "repositories" {
  description = "Repository name -> its tags, and the policy documents (JSON) of its aws_ecr_lifecycle_policy and aws_ecr_repository_policy; null builds neither. Tags are always IMMUTABLE, every push is scanned and images are encrypted: those are not arguments."
  type = map(object({
    tags              = optional(map(string), {})
    lifecycle_policy  = optional(string)
    repository_policy = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in keys(var.repositories) : can(regex("^[a-z0-9]+([._-][a-z0-9]+)*$", r))])
    error_message = "Repository names are lowercase letters and digits, separated by . _ or -."
  }
}

variable "replication_configuration" {
  description = "The registry's aws_ecr_replication_configuration: its rule list, each with destination (region, registry_id) and repository_filter (filter, filter_type). null builds none. The registry has one, so one stack per account and region sets it."
  type = object({
    rule = list(object({
      destination = list(object({
        region      = string
        registry_id = string
      }))
      repository_filter = optional(list(object({
        filter      = string
        filter_type = string
      })), [])
    }))
  })
  default = null

  validation {
    condition     = var.replication_configuration == null || alltrue(flatten([for r in try(var.replication_configuration.rule, []) : [for d in r.destination : can(regex("^[0-9]{12}$", d.registry_id))]]))
    error_message = "registry_id is a 12-digit account ID."
  }
}
