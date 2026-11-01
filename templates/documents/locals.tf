locals {
  config_dir = coalesce(var.config_dir, path.root)
  documents  = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
}
