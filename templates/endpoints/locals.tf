locals {
  config_dir = coalesce(var.config_dir, path.root)
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  settings   = merge({ tier = "private", interface = [], gateway = [] }, try(yamldecode(file("${local.config_dir}/endpoints.yml")), {}))

  problems = concat(
    fileexists("${local.config_dir}/endpoints.yml") ? [] : ["there is no endpoints.yml"],
    [for k in keys(local.settings) : "endpoints.yml: unknown key ${k} (keys are tier, interface and gateway)" if !contains(["tier", "interface", "gateway"], k)],
    contains(keys(local.network.subnets), local.settings.tier) ? [] : ["endpoints.yml: ${var.environment}'s VPC in ${var.region} has no ${local.settings.tier} tier"],
  )
}
