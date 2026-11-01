locals {
  config_dir   = coalesce(var.config_dir, path.root)
  certificates = coalesce(try(yamldecode(file("${local.config_dir}/certificates.yml")), null), {})
}
