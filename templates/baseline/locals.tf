locals {
  regions = toset(concat([var.region], [for key in keys(module.ip_plan.networks) : split("/", key)[1]]))
}
