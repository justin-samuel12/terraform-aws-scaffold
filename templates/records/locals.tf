locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  keys       = ["zone", "private", "name", "load_balancer", "server", "cname"]

  problems = concat(
    [for n, f in local.files : "${n}.yml: keys are ${join(", ", local.keys)}" if !alltrue([for k in try(keys(f), []) : contains(local.keys, k)])],
    [for n, f in local.files : "${n}.yml: needs a zone and exactly one of load_balancer, server or cname" if !can(f.zone) || length(compact([try(f.load_balancer, null), try(f.server, null), try(f.cname, null)])) != 1],
  )
  records = { for n, f in local.files : n => f if length(local.problems) == 0 }
}
