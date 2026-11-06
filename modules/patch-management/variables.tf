variable "environment" {
  description = "The environment patched: its instances carry the tag PatchGroup = <environment>, and every baseline and window is named <environment>-<name>."
  type        = string
}

variable "patch_baselines" {
  description = "Baseline name -> its aws_ssm_patch_baseline arguments. Each is registered for the environment's patch group, so there is at most one per operating_system."
  type = map(object({
    description      = optional(string)
    operating_system = string
    approved_patches = optional(list(string))
    rejected_patches = optional(list(string))
    approval_rule = optional(list(object({
      approve_after_days  = optional(number)
      compliance_level    = optional(string)
      enable_non_security = optional(bool)
      patch_filter = list(object({
        key    = string
        values = list(string)
      }))
    })), [])
    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = length(distinct([for b in values(var.patch_baselines) : b.operating_system])) == length(var.patch_baselines)
    error_message = "A patch group takes one baseline per operating_system."
  }
}

variable "maintenance_windows" {
  description = "Window name -> its aws_ssm_maintenance_window arguments. Each runs AWS-RunPatchBaseline (Install, rebooting if needed) on the instances tagged PatchGroup = <environment>, a quarter at a time."
  type = map(object({
    description       = optional(string)
    schedule          = string
    schedule_timezone = optional(string)
    duration          = number
    cutoff            = number
    enabled           = optional(bool)
    tags              = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for w in values(var.maintenance_windows) : can(regex("^(cron|rate)\\(.+\\)$", w.schedule))])
    error_message = "schedule is cron(...) or rate(...)."
  }
}
