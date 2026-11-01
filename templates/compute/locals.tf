locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  group_keys = ["count", "type", "image", "tier", "security_groups", "role", "root_size", "volumes", "protect", "backup", "user_data", "targets", "members", "tags"]
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  servers    = module.placement.servers

  problems = concat(
    [for group, f in local.files : "${group}.yml: keys are ${join(", ", local.group_keys)}" if !alltrue([for k in try(keys(f), []) : contains(local.group_keys, k)])],
    [for group, f in local.files : "${group}.yml: needs image and type" if !can(f.image) || !can(f.type)],
    [for group, f in local.files : "${group}.yml: needs a role, an instance profile from the iam stack, so its permissions are chosen" if !can(f.role)],
    module.placement.problems,
  )
  usable = length(local.problems) == 0
}
