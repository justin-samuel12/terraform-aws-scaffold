locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  groups = var.containerized ? ["primary-${var.environment}"] : var.groups

  existing = try(data.external.ownership[0].result, { exists = "false", owner = "" })
  manage   = !var.containerized || local.existing.exists != "true" || local.existing.owner == "" || local.existing.owner == var.environment

  traffic_control = length(var.target_group_names) > 0 && var.servers_behind_load_balancer > 1
}
