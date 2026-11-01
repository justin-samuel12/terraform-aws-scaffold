variable "config_path" {
  description = "The config folder, absolute or relative to this module: global.yml and one <region>.yml per region. null: the repository's config/. Tests point it at their own."
  type        = string
  default     = "../../config"
  nullable    = false

  validation {
    condition     = length(fileset(startswith(var.config_path, "/") ? var.config_path : "${path.module}/${var.config_path}", "*.yml")) > 0
    error_message = "No <region>.yml files in ${var.config_path}."
  }
}
