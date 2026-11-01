locals {
  config_dir  = coalesce(var.config_dir, path.root)
  files       = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  app_keys    = ["servers", "port", "health", "target", "routes", "targets", "deploy", "names"]
  server_keys = ["count", "type", "image", "tier", "role", "security_groups", "root_size", "volumes", "backup", "user_data", "members", "tags"]
  network     = module.ip_plan.networks["${var.environment}/${var.region}"]
  servers     = module.placement.servers

  # Every route and name, flattened, so they can be checked across applications and looked up once.
  routes = flatten([for app, f in local.files : [for r in try(f.routes, []) : {
    app           = app
    load_balancer = r.load_balancer
    listener      = tostring(try(r.listener, 443))
    hosts         = try(tolist(r.hosts), [])
    paths         = try(tolist(r.paths), [])
    priority      = r.priority
  }]])
  names = flatten([for app, f in local.files : [for n in try(f.names, []) : {
    app           = app
    name          = "${n.name}.${n.zone}"
    zone          = n.zone
    private       = try(n.private, false)
    load_balancer = try(n.load_balancer, f.routes[0].load_balancer, split("/", keys(f.targets)[0])[0], null)
  }]])

  targets = { for app, f in local.files : app => { for t, port in try(f.targets, {}) : t => port } }

  listener_keys = distinct([for r in local.routes : "${r.load_balancer}:${r.listener}"])
  priorities    = [for r in local.routes : "${r.load_balancer}:${r.listener}:${r.priority}"]
  matches       = flatten([for r in local.routes : [for h in concat(r.hosts, length(r.hosts) == 0 ? ["*"] : []) : [for p in concat(r.paths, length(r.paths) == 0 ? ["*"] : []) : "${r.load_balancer}:${r.listener} ${h}${p == "*" ? "" : p}"]]])

  problems = concat(
    [for app, f in local.files : "${app}.yml: keys are ${join(", ", local.app_keys)}" if !alltrue([for k in try(keys(f), []) : contains(local.app_keys, k)])],
    [for app, f in local.files : "${app}.yml: servers keys are ${join(", ", local.server_keys)} (applications are stateless: anything holding state belongs in compute, with protect)" if !alltrue([for k in try(keys(f.servers), []) : contains(local.server_keys, k)])],
    [for app, f in local.files : "${app}.yml: servers needs image, type and role" if !alltrue([for k in ["image", "type", "role"] : can(f.servers[k])])],
    [for app, f in local.files : "${app}.yml: the name is 23 characters at most, lowercase letters, digits and hyphens" if !can(regex("^[a-z][a-z0-9-]{0,22}$", app))],
    [for app, f in local.files : "${app}.yml: routes need a port" if length(try(f.routes, [])) > 0 && !can(f.port)],
    [for app, f in local.files : "${app}.yml: target sets up the application's own target group, which only routes create" if can(f.target) && length(try(f.routes, [])) == 0],
    [for app, f in local.files : "${app}.yml: targets are <load balancer>/<target>: <port>" if !alltrue([for t, port in try(f.targets, {}) : can(regex("^[a-z0-9-]+/[a-z0-9-]+$", t)) && can(tonumber(port))])],
    [for r in local.routes : "${r.app}.yml: route priorities are 1000 and up (1 to 999 are the load balancer's own rules)" if r.priority < 1000],
    [for app, f in local.files : "${app}.yml: names need a load balancer: a route, or load_balancer on the name" if length([for n in local.names : n if n.app == app && n.load_balancer == null]) > 0],
    [for p in distinct(local.priorities) : "priority ${split(":", p)[2]} on ${split(":", p)[0]}:${split(":", p)[1]} is used by more than one route" if length([for x in local.priorities : x if x == p]) > 1],
    [for m in distinct(local.matches) : "${m} is claimed by more than one route" if length([for x in local.matches : x if x == m]) > 1],
    module.placement.problems,
  )
  usable = length(local.problems) == 0
}
