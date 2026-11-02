locals {
  config_dir = coalesce(var.config_dir, path.root)
  settings   = merge({ idle_timeout_minutes = 20, max_session_minutes = 480, retention_in_days = 365 }, try(yamldecode(file("${local.config_dir}/session-manager.yml")), {}))
}
