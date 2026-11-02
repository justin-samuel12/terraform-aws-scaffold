locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  keys       = ["engine", "engine_version", "instance_class", "allocated_storage", "max_allocated_storage", "multi_az", "security_groups"]

  problems = concat(
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.keys)}" if !alltrue([for k in try(keys(f), []) : contains(local.keys, k)])],
    [for name, f in local.files : "${name}.yml: needs engine, engine_version, instance_class and allocated_storage" if !alltrue([for k in ["engine", "engine_version", "instance_class", "allocated_storage"] : can(f[k])])],
  )
  databases = { for name, f in local.files : name => f if alltrue([for k in ["engine", "engine_version", "instance_class", "allocated_storage"] : can(f[k])]) }
}
