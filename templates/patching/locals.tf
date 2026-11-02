locals {
  config_dir = coalesce(var.config_dir, path.root)
  settings   = merge({ schedule = "cron(0 7 ? * SUN *)", duration = 3, approve_after_days = 7 }, try(yamldecode(file("${local.config_dir}/patching.yml")), {}))
}
