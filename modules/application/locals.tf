locals {
  routed   = length(var.routes) > 0
  deployed = var.deploy != null

  target_group_names = concat(aws_lb_target_group.application[*].name, [for t in values(var.targets) : t.name])

  deployment_configs = {
    "one-at-a-time"  = "CodeDeployDefault.OneAtATime"
    "half-at-a-time" = "CodeDeployDefault.HalfAtATime"
    "all-at-once"    = "CodeDeployDefault.AllAtOnce"
  }
}
