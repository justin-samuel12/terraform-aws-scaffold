locals {
  pattern = "^[a-z0-9][a-z0-9-]*/v[0-9]+$"
  refs    = { for name, f in var.files : name => tostring(f.blueprint) if can(f.blueprint) }
  blueprints = {
    for ref in distinct(values(local.refs)) : ref => can(regex(local.pattern, ref)) ? try(yamldecode(file("${var.dir}/${ref}.yml")), null) : null
  }

  paths = {
    for name, ref in local.refs : name => flatten([
      for k, v in var.files[name] : can(keys(v)) ? flatten([
        for k2, v2 in v : can(keys(v2)) ? [for k3, v3 in v2 : "${k}.${k2}.${k3}"] : ["${k}.${k2}"]
      ]) : [k] if k != "blueprint"
    ])
  }

  bodies = {
    for name, ref in local.refs : name => try(yamldecode(replace(replace(replace(
      yamlencode(local.blueprints[ref][var.body]),
      "{app}", name), "{environment}", var.environment), "{region}", var.region
    )), {})
  }
  adds     = { for ref in distinct(values(local.refs)) : ref => try([for k in local.blueprints[ref].adds : tostring(k)], []) }
  top_adds = { for ref, list in local.adds : ref => [for a in list : a if length(split(".", a)) == 1] }
  sub_adds = { for ref, list in local.adds : ref => { for a in list : a => split(".", a) if length(split(".", a)) == 2 } }
  base = {
    for name, ref in local.refs : name => merge(
      local.bodies[name],
      {
        for k, v in var.files[name] : k => try(merge(local.bodies[name][k], {
          for k2 in keys(v) : k2 => try(merge(local.bodies[name][k][k2], { for k3 in keys(v[k2]) : k3 => v[k2][k3] }), v[k2])
        }), v) if !contains(concat(["blueprint"], local.top_adds[ref]), k)
      },
      {
        for k in local.top_adds[ref] : k => [for x in distinct(concat(try(tolist(local.bodies[name][k]), []), try(tolist(var.files[name][k]), []))) : x]
        if can(var.files[name][k]) || can(local.bodies[name][k])
      },
    )
  }

  merged = {
    for name, ref in local.refs : name => merge(local.base[name], {
      for parent in distinct([for a, path in local.sub_adds[ref] : path[0]]) : parent => merge(local.base[name][parent], {
        for a, path in local.sub_adds[ref] : path[1] => [
          for x in distinct(concat(try(tolist(local.bodies[name][path[0]][path[1]]), []), try(tolist(var.files[name][path[0]][path[1]]), []))) : x
        ] if path[0] == parent && (can(var.files[name][path[0]][path[1]]) || can(local.bodies[name][path[0]][path[1]]))
      }) if can(keys(local.base[name][parent]))
    })
  }

  choices = {
    for ref, b in local.blueprints : ref => {
      for key, list in var.choices : key => try(b.environments[var.environment][list], b[list], null)
    } if b != null
  }
  scope = { for ref, b in local.blueprints : ref => { for key, list in var.choices : key => can(b.environments[var.environment][list]) ? " in ${var.environment}" : "" } if b != null }
  names = { for ref, c in local.choices : ref => { for key, list in c : key => try([for x in list.allowed : tostring(x)], []) } }
  chosen = {
    for name, ref in local.refs : name => {
      for key, list in try(local.choices[ref], {}) : key => try(tostring(var.files[name][key]), tostring(list.default), null)
    }
  }
  expanded = {
    for name, ref in local.refs : name => merge(
      local.merged[name],
      { for key, value in local.chosen[name] : key => value if value != null },
    )
  }

  sections    = concat(["description", "allows", "adds", "requires", "environments", var.body], values(var.choices), var.sections)
  versions_of = { for ref in distinct(values(local.refs)) : ref => [for v in fileset("${var.dir}/${split("/", ref)[0]}", "v*.yml") : trimsuffix(v, ".yml")] }

  problems = concat(
    [for name, ref in local.refs : "${name}.yml: blueprint ${ref} is <name>/v<number>, such as ${var.example}" if !can(regex(local.pattern, ref))],
    [
      for name, ref in local.refs : "${name}.yml: blueprint ${ref} not found: ${var.label}/${split("/", ref)[0]}/ has ${length(local.versions_of[ref]) == 0 ? "nothing" : join(", ", local.versions_of[ref])}"
      if can(regex(local.pattern, ref)) && local.blueprints[ref] == null
    ],
    [for ref, b in local.blueprints : "${var.label}/${ref}.yml: a blueprint holds ${join(", ", local.sections)}" if b != null && !alltrue([for k in try(keys(b), ["?"]) : contains(local.sections, k)])],
    distinct([for name, ref in local.refs : "${var.label}/${ref}.yml: it needs ${var.body}: the settings every app on it gets" if local.blueprints[ref] != null && !can(keys(local.blueprints[ref][var.body]))]),
    flatten([for name, paths in local.paths : [
      for p in paths : "${name}.yml: ${p} is set by blueprint ${local.refs[name]}; an app on it may set ${join(", ", try(local.blueprints[local.refs[name]].allows, []))}"
      if !contains(concat(["tags"], try(local.blueprints[local.refs[name]].requires, [])), split(".", p)[0])
      && !anytrue([for a in local.adds[local.refs[name]] : p == a || startswith(p, "${a}.")])
      && !anytrue([for a in try(local.blueprints[local.refs[name]].allows, []) : can(regex("^${replace(replace(a, ".", "\\."), "*", "[^.]+")}(\\..*)?$", p))])
    ] if local.blueprints[local.refs[name]] != null]),
    flatten([for name, ref in local.refs : [
      for r in try(local.blueprints[ref].requires, []) : "${name}.yml: blueprint ${ref} needs ${r}" if !can(var.files[name][r])
    ] if local.blueprints[ref] != null]),
    flatten([for name, ref in local.refs : [
      for k in local.top_adds[ref] : "${name}.yml: ${k} is a list, added to blueprint ${ref}'s" if can(var.files[name][k]) && !can(tolist(var.files[name][k]))
    ]]),
    flatten([for name, ref in local.refs : [
      for a, path in local.sub_adds[ref] : "${name}.yml: ${a} is a list, added to blueprint ${ref}'s" if can(var.files[name][path[0]][path[1]]) && !can(tolist(var.files[name][path[0]][path[1]]))
    ]]),
    distinct([for name, ref in local.refs : "${var.label}/${ref}.yml: adds takes a key or a parent.key, such as vpc_security_group_ids or network_configuration.security_groups" if anytrue([for a in local.adds[ref] : length(split(".", a)) > 2])]),
    flatten([for ref, c in local.choices : [
      for key, list in c : "${var.label}/${ref}.yml: ${var.choices[key]}${local.scope[ref][key]} needs allowed and a default that is one of them"
      if list != null && !try(contains(local.names[ref][key], tostring(list.default)), false)
    ]]),
    flatten([for ref, b in local.blueprints : [
      for key, list in var.choices : "${var.label}/${ref}.yml: ${var.body}.${key} is set as ${list}.default, so allowed and default sit together"
      if can(b[var.body][key])
    ] if b != null]),
    flatten([for ref, b in local.blueprints : [
      for environment, e in try(b.environments, {}) : "${var.label}/${ref}.yml: environments.${environment} may set only ${join(", ", values(var.choices))}"
      if !alltrue([for k in try(keys(e), ["?"]) : contains(values(var.choices), k)])
    ] if b != null]),
    flatten([for name, ref in local.refs : [
      for key, value in local.chosen[name] : "${name}.yml: ${key} ${value} is not one blueprint ${ref} offers${local.scope[ref][key]}: ${join(", ", local.names[ref][key])}"
      if can(var.files[name][key]) && local.choices[ref][key] != null && !contains(local.names[ref][key], value)
    ] if can(local.choices[ref])]),
  )
}
