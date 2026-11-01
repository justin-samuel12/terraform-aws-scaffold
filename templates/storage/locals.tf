locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  keys       = ["tier", "security_groups", "access_points"]
  tiers      = toset([for f in values(local.files) : try(f.tier, "data")])

  problems = [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.keys)}" if !alltrue([for k in try(keys(f), []) : contains(local.keys, k)])]
}
