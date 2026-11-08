variable "documents" {
  description = "Policy name -> its statements, as the deployment-policies module's documents output gives them."
  type        = any
}

variable "requests" {
  description = "Name -> a request to decide: the policies of the principal making it, the action, the resource ARN, and the request context (condition key -> values)."
  type = map(object({
    policies = list(string)
    action   = string
    resource = string
    context  = optional(map(list(string)), {})
  }))
}
