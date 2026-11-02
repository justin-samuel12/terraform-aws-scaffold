locals {
  config_dir   = coalesce(var.config_dir, path.root)
  settings     = merge({ keep_images = 30, untagged_days = 14 }, try(yamldecode(file("${local.config_dir}/ecr.yml")), {}))
  repositories = toset(coalesce(try(local.settings.repositories, null), []))

  # Copies go to every other region with a file in config/.
  replicate_to = toset([for key in keys(module.ip_plan.networks) : split("/", key)[1] if split("/", key)[1] != var.region])

  # Every environment's account other than this one, so their servers can pull.
  pull_accounts = toset([for env, account in module.ip_plan.accounts.environments : account if account != "" && account != try(module.ip_plan.accounts.hubs[var.region], "")])
}
