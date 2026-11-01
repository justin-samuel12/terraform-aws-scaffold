locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }

  web_acls = {
    for name, f in local.files : name => {
      managed_rules  = try(tolist(f.managed_rules), null)
      rate_limit     = try(f.rate_limit, 2000)
      load_balancers = try(tolist(f.load_balancers), [])
    }
  }
}
