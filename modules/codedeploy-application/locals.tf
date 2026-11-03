locals {
  # A shared, containerized application has one group per environment; any other has a group per branch it deploys from.
  groups = var.containerized ? ["primary-${var.environment}"] : var.groups

  # A shared application is created by the first environment to need it, and tagged as its; the others only add their group.
  existing = try(data.external.ownership[0].result, { exists = "false", owner = "" })
  manage   = !var.containerized || local.existing.exists != "true" || local.existing.owner == "" || local.existing.owner == var.environment

  traffic_control = length(var.target_group_names) > 0 && var.servers_behind_load_balancer > 1
}
