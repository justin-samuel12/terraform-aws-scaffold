locals {
  # Every region with a file in config/, so a new region is covered as soon as it is added.
  regions = toset(concat([var.region], [for key in keys(module.ip_plan.networks) : split("/", key)[1]]))
}
