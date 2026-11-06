variable "files" {
  description = "A stack's files, by name (the file name without .yml), as read from YAML. Those with blueprint: <name>/v<n> are expanded; the rest pass through."
  type        = any
}

variable "dir" {
  description = "The stack's blueprint folder, holding <name>/v<n>.yml: blueprints/<stack>/."
  type        = string
}

variable "label" {
  description = "How messages name that folder, such as blueprints/compute."
  type        = string
}

variable "body" {
  description = "The key in a blueprint holding the settings every app on it gets: group for compute, service for containers, database for databases."
  type        = string
}

variable "example" {
  description = "A blueprint reference for messages, such as backend-service/v1."
  type        = string
}

variable "choices" {
  description = "Keys an app's file may set only to a value its blueprint lists: key -> the blueprint's list of allowed values and default, such as { instance_type = \"instance_types\" }."
  type        = map(string)
  default     = {}
}

variable "sections" {
  description = "Top-level sections a blueprint may hold beyond description, allows, adds, requires, environments, the body and the choice lists, such as role for compute."
  type        = list(string)
  default     = []
}

variable "environment" {
  description = "Fills in {environment}."
  type        = string
}

variable "region" {
  description = "Fills in {region}."
  type        = string
}
