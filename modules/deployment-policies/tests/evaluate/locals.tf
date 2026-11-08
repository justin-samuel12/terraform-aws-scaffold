locals {
  negated   = ["StringNotEquals", "StringNotLike", "ArnNotEquals", "ArnNotLike"]
  operators = ["StringEquals", "StringNotEquals", "StringLike", "StringNotLike", "ArnEquals", "ArnNotEquals", "ArnLike", "ArnNotLike", "Null", "Bool", "ForAnyValue:StringEquals", "ForAllValues:StringNotEquals"]

  statements = {
    for name, r in var.requests : name => flatten([
      for p in r.policies : [
        for s in var.documents[p] : {
          policy       = p
          sid          = try(s.Sid, "")
          effect       = s.Effect
          action       = try(s.Action, null) == null ? null : flatten([s.Action])
          not_action   = try(s.NotAction, null) == null ? null : flatten([s.NotAction])
          resource     = try(s.Resource, null) == null ? null : flatten([s.Resource])
          not_resource = try(s.NotResource, null) == null ? null : flatten([s.NotResource])
          conditions = flatten([
            for op, keys in try(s.Condition, {}) : [
              for key, values in keys : {
                op     = trimsuffix(op, "IfExists")
                exists = endswith(op, "IfExists")
                key    = key
                values = [for v in flatten([values]) : tostring(v)]
              }
            ]
          ])
        }
      ]
    ])
  }

  evaluated = {
    for name, r in var.requests : name => [
      for s in local.statements[name] : {
        policy      = s.policy
        sid         = s.sid
        effect      = s.effect
        unsupported = anytrue([for c in s.conditions : !contains(local.operators, c.op)])
        hit = alltrue([
          s.action != null ? anytrue([for a in s.action : can(regex("^${replace(replace(replace(lower(a), ".", "\\."), "*", ".*"), "?", ".")}$", lower(r.action)))]) : !anytrue([for a in s.not_action : can(regex("^${replace(replace(replace(lower(a), ".", "\\."), "*", ".*"), "?", ".")}$", lower(r.action)))]),
          s.resource != null ? anytrue([for p in s.resource : can(regex("^${replace(replace(replace(p, ".", "\\."), "*", ".*"), "?", ".")}$", r.resource))]) : !anytrue([for p in s.not_resource : can(regex("^${replace(replace(replace(p, ".", "\\."), "*", ".*"), "?", ".")}$", r.resource))]),
          alltrue([
            for c in s.conditions : (
              lookup(r.context, c.key, null) == null ? (
                c.op == "Null" ? contains(c.values, "true") : c.exists || contains(local.negated, c.op) || c.op == "ForAllValues:StringNotEquals"
                ) : (
                c.op == "Null" ? contains(c.values, "false") :
                c.op == "Bool" ? contains(c.values, r.context[c.key][0]) :
                c.op == "ForAnyValue:StringEquals" ? length(setintersection(c.values, r.context[c.key])) > 0 :
                c.op == "ForAllValues:StringNotEquals" ? length(setintersection(c.values, r.context[c.key])) == 0 :
                contains(["StringEquals", "ArnEquals"], c.op) ? length(setintersection(c.values, r.context[c.key])) > 0 :
                contains(["StringNotEquals", "ArnNotEquals"], c.op) ? length(setintersection(c.values, r.context[c.key])) == 0 :
                contains(["StringLike", "ArnLike"], c.op) ? anytrue(flatten([for v in c.values : [for x in r.context[c.key] : can(regex("^${replace(replace(replace(v, ".", "\\."), "*", ".*"), "?", ".")}$", x))]])) :
                contains(["StringNotLike", "ArnNotLike"], c.op) ? !anytrue(flatten([for v in c.values : [for x in r.context[c.key] : can(regex("^${replace(replace(replace(v, ".", "\\."), "*", ".*"), "?", ".")}$", x))]])) :
                false
              )
            )
          ]),
        ])
      }
    ]
  }

  decisions = {
    for name, list in local.evaluated : name => (
      anytrue([for s in list : s.unsupported]) ? "unsupported" :
      anytrue([for s in list : s.hit && s.effect == "Deny"]) ? "deny" :
      anytrue([for s in list : s.hit && s.effect == "Allow"]) ? "allow" :
      "implicit-deny"
    )
  }
}
