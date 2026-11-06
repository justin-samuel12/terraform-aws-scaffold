locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  kinds      = ["role", "policy", "instance-profile"]
  paths      = [for path in fileset(local.config_dir, "**/*.yml") : path]
  found      = { for path in local.paths : "${split("/", path)[0]}/${trimsuffix(basename(path), ".yml")}" => path... if length(split("/", path)) > 1 && contains(local.kinds, split("/", path)[0]) }
  files      = { for key, paths in local.found : key => try(yamldecode(file("${local.config_dir}/${sort(paths)[0]}")), null) }
  roles      = { for key, f in local.files : trimprefix(key, "role/") => f if startswith(key, "role/") }
  policies   = { for key, f in local.files : trimprefix(key, "policy/") => f if startswith(key, "policy/") }
  profiles   = { for key, f in local.files : trimprefix(key, "instance-profile/") => f if startswith(key, "instance-profile/") }

  role_keys      = ["description", "assume_role_policy", "managed_policy_arns", "statement"]
  policy_keys    = ["description", "statement"]
  statement_keys = ["effect", "actions", "resources", "condition"]
  trust_keys     = ["effect", "actions", "principals", "condition"]

  written = flatten([for key, f in local.files : concat(
    [for s in try(concat(f.statement, []), []) : { file = "${key}.yml", keys = local.statement_keys, s = s }],
    [for s in try(concat(f.assume_role_policy.statement, []), []) : { file = "${key}.yml", keys = local.trust_keys, s = s }],
  ) if !startswith(key, "instance-profile/")])

  statements = {
    for key, f in local.files : key => [
      for s in try(concat(f.statement, []), []) : {
        effect    = try(tostring(s.effect), "Allow")
        actions   = [for a in try(concat(s.actions, []), []) : tostring(a)]
        resources = [for r in try(concat(s.resources, []), []) : tostring(r)]
        condition = [for c in try(concat(s.condition, []), []) : { test = try(tostring(c.test), ""), variable = try(tostring(c.variable), ""), values = [for v in try(concat(c.values, []), []) : tostring(v)] }]
      }
    ] if !startswith(key, "instance-profile/")
  }

  trust = {
    for name, f in local.roles : name => jsonencode({
      Version = "2012-10-17"
      Statement = [for s in try(concat(f.assume_role_policy.statement, []), []) : merge(
        { Effect = try(tostring(s.effect), "Allow"), Action = [for a in try(concat(s.actions, []), []) : tostring(a)] },
        { Principal = { for t in distinct([for p in try(concat(s.principals, []), []) : try(tostring(p.type), "")]) : t => flatten([for p in try(concat(s.principals, []), []) : [for i in try(concat(p.identifiers, []), []) : tostring(i)] if try(tostring(p.type), "") == t]) } },
        length(try(concat(s.condition, []), [])) == 0 ? {} : { Condition = { for test in distinct([for c in concat(s.condition, []) : try(tostring(c.test), "")]) : test => { for c in concat(s.condition, []) : try(tostring(c.variable), "") => [for v in try(concat(c.values, []), []) : tostring(v)] if try(tostring(c.test), "") == test } } },
      )]
    })
  }

  attached = { for name, f in local.roles : name => [for p in try(concat(f.managed_policy_arns, []), []) : tostring(p)] }

  problems = concat(
    [for key, paths in local.found : "${key}.yml is in more than one folder (${join(", ", sort(paths))}); a ${split("/", key)[0]}'s name is its file's, so it must be unique" if length(paths) > 1],
    [for path in local.paths : "${path}: a file belongs in role/ (an aws_iam_role), policy/ (an aws_iam_policy) or instance-profile/ (an aws_iam_instance_profile)" if length(split("/", path)) == 1 || !contains(local.kinds, split("/", path)[0])],
    [for name, f in local.roles : "role/${name}.yml: keys are ${join(", ", local.role_keys)}" if !alltrue([for k in try(keys(f), ["?"]) : contains(local.role_keys, k)])],
    [for name, f in local.policies : "policy/${name}.yml: keys are ${join(", ", local.policy_keys)}" if !alltrue([for k in try(keys(f), ["?"]) : contains(local.policy_keys, k)])],
    [for name, f in local.profiles : "instance-profile/${name}.yml: role is its only key, a role in role/" if !(length(try(keys(f), [])) == 1 && can(tostring(f.role)))],
    [for name, f in local.profiles : "instance-profile/${name}.yml: role ${f.role} is not a role in this stack (a file named role/${f.role}.yml)" if can(tostring(f.role)) && !contains(keys(local.roles), try(tostring(f.role), ""))],
    [for key, f in local.files : "${key}.yml: needs a description" if !startswith(key, "instance-profile/") && trimspace(try(tostring(f.description), "")) == ""],
    [for name, f in local.roles : "role/${name}.yml: needs assume_role_policy, a statement list naming who may assume the role" if length(try(concat(f.assume_role_policy.statement, []), [])) == 0 || length(try(keys(f.assume_role_policy), [])) != 1],
    [for name, f in local.policies : "policy/${name}.yml: needs a statement list" if length(try(concat(f.statement, []), [])) == 0],
    [for w in local.written : "${w.file}: a statement takes ${join(", ", w.keys)}, as aws_iam_policy_document does" if !alltrue([for k in try(keys(w.s), ["?"]) : contains(w.keys, k)])],
    [for w in local.written : "${w.file}: a statement needs ${contains(w.keys, "principals") ? "actions and principals" : "actions and resources"}" if length(try(concat(w.s.actions, []), [])) == 0 || length(try(concat(contains(w.keys, "principals") ? w.s.principals : w.s.resources, []), [])) == 0],
    [for w in local.written : "${w.file}: a principal takes type and identifiers; a condition takes test, variable and values" if !alltrue(concat([for p in try(concat(w.s.principals, []), []) : can(tostring(p.type)) && can(concat(p.identifiers, [])) && try(length(keys(p)), 0) == 2], [for c in try(concat(w.s.condition, []), []) : can(tostring(c.test)) && can(tostring(c.variable)) && can(concat(c.values, [])) && try(length(keys(c)), 0) == 3]))],
    flatten([for name, arns in local.attached : [for p in arns : "role/${name}.yml: managed_policy_arns ${p} is not a policy in this stack (a file named policy/${p}.yml) or an ARN" if !startswith(p, "arn:") && !contains(keys(local.policies), p)]]),
  )

  module_policies = { for name, f in local.policies : name => { description = try(tostring(f.description), ""), statements = local.statements["policy/${name}"] } }
  module_roles = {
    for name, f in local.roles : name => {
      description        = try(tostring(f.description), "")
      assume_role_policy = local.trust[name]
      policies           = [for p in local.attached[name] : p if !startswith(p, "arn:")]
      policy_arns        = [for p in local.attached[name] : p if startswith(p, "arn:")]
      statements         = local.statements["role/${name}"]
    }
  }
}
