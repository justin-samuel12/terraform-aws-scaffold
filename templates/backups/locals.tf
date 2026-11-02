locals {
  config_dir = coalesce(var.config_dir, path.root)
  settings   = merge({ daily_retention_days = 35, monthly_retention_days = 365, copy = true, vault_lock = "governance" }, try(yamldecode(file("${local.config_dir}/backups.yml")), {}))

  # Copies go to the other region in config/ (the first, if there are several).
  other_regions = sort(distinct([for key in keys(module.ip_plan.networks) : split("/", key)[1] if split("/", key)[1] != var.region]))
  copy_region   = local.settings.copy && length(local.other_regions) > 0 ? local.other_regions[0] : null
}
