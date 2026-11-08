variable "environment" {
  description = "Which environment to render: shared, for the hub's account, or a spoke."
  type        = string
  default     = "staging"
}
