locals {
  config_dir = coalesce(var.config_dir, path.root)
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  file_keys  = ["load_balancer_type", "internal", "tier", "security_groups", "certificate", "listeners", "targets", "rules"]

  load_balancers = {
    for name, f in local.files : name => {
      type            = try(f.load_balancer_type, "application")
      internal        = try(tobool(f.internal), true)
      tier            = try(f.tier, try(tobool(f.internal), true) ? "private" : "public")
      security_groups = try(tolist(f.security_groups), [])
      certificate     = try(f.certificate, null)
      listeners       = { for port, l in try(f.listeners, {}) : tostring(port) => { protocol = l.protocol, target = try(l.target, null), redirect = try(l.redirect, false) } }
      targets         = { for target, t in try(f.targets, {}) : target => { port = t.port, protocol = t.protocol, health_check_path = try(t.health_check.path, null) } }
      rules = {
        for rule, r in try(f.rules, {}) : rule => {
          listener       = tostring(r.listener)
          priority       = r.priority
          hosts          = try(tolist(r.host_header), [])
          paths          = try(tolist(r.path_pattern), [])
          target         = try(r.target, null)
          redirect       = try(r.redirect, null) == null ? null : { host = try(r.redirect.host, "#{host}"), path = try(r.redirect.path, "/#{path}"), query = try(r.redirect.query, "#{query}"), status_code = try(r.redirect.status_code, "HTTP_301") }
          fixed_response = try(r.fixed_response, null) == null ? null : { status_code = tostring(r.fixed_response.status_code), content_type = try(r.fixed_response.content_type, "text/plain"), body = try(r.fixed_response.message_body, "") }
        }
      }
    }
  }

  usable_tiers = toset([for lb in local.load_balancers : lb.tier if contains(keys(local.network.subnets), lb.tier)])
  problems = concat(
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, f in local.files : "${name}.yml: internal is true or false" if !can(tobool(try(f.internal, true)))],
    [for name, lb in local.load_balancers : "${name}.yml: ${var.environment}'s VPC in ${var.region} has no ${lb.tier} tier${lb.internal ? "" : "; an internet-facing load balancer needs a public tier (public: true in config)"}" if !contains(keys(local.network.subnets), lb.tier)],
  )
}
