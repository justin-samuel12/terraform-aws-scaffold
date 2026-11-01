locals {
  config_dir   = coalesce(var.config_dir, path.root)
  files        = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  policy_files = { for name in fileset("${local.config_dir}/policies", "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/policies/${name}")) }

  policies = {
    for name, f in local.policy_files : name => {
      description = try(f.description, "")
      statements = [for s in try(f.statements, []) : {
        effect    = try(s.effect, "Allow")
        actions   = tolist(s.actions)
        resources = tolist(s.resources)
      }]
    }
  }

  roles = {
    for name, f in local.files : name => {
      description      = try(f.description, "")
      services         = toset(try(f.services, []))
      managed_policies = try(tolist(f.managed_policies), [])
      policies         = try(tolist(f.policies), [])
      statements = [for s in try(f.statements, []) : {
        effect    = try(s.effect, "Allow")
        actions   = tolist(s.actions)
        resources = tolist(s.resources)
      }]
    }
  }
}
