locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }

  file_keys       = concat(["default_action", "rule", "visibility_config"], var.scope == "REGIONAL" ? ["resource_arns"] : [])
  rule_keys       = ["name", "priority", "action", "override_action", "statement", "visibility_config"]
  statement_keys  = ["managed_rule_group_statement", "rate_based_statement"]
  managed_keys    = ["name", "vendor_name"]
  rate_keys       = ["limit", "aggregate_key_type"]
  visibility_keys = ["cloudwatch_metrics_enabled", "metric_name", "sampled_requests_enabled"]
  blocks = {
    default_action  = ["allow", "block"]
    action          = ["allow", "block", "count"]
    override_action = ["none", "count"]
  }

  rules = { for name, f in local.files : name => try([for r in f.rule : r if !can(keys(f.rule))], []) }

  web_acls = {
    for name, f in local.files : name => {
      default_action = { for k in local.blocks.default_action : k => contains(try(keys(f.default_action), []), k) ? {} : null }
      visibility_config = {
        cloudwatch_metrics_enabled = try(tobool(f.visibility_config.cloudwatch_metrics_enabled), null)
        metric_name                = try(tostring(f.visibility_config.metric_name), null)
        sampled_requests_enabled   = try(tobool(f.visibility_config.sampled_requests_enabled), null)
      }
      rule = [
        for r in local.rules[name] : {
          name            = try(tostring(r.name), "")
          priority        = try(tonumber(r.priority), -1)
          action          = can(keys(r.action)) ? { for k in local.blocks.action : k => contains(keys(r.action), k) ? {} : null } : null
          override_action = can(keys(r.override_action)) ? { for k in local.blocks.override_action : k => contains(keys(r.override_action), k) ? {} : null } : null
          statement = {
            managed_rule_group_statement = try(r.statement.managed_rule_group_statement, null) == null ? null : {
              name        = try(tostring(r.statement.managed_rule_group_statement.name), "")
              vendor_name = try(tostring(r.statement.managed_rule_group_statement.vendor_name), "")
            }
            rate_based_statement = try(r.statement.rate_based_statement, null) == null ? null : {
              limit              = try(tonumber(r.statement.rate_based_statement.limit), 0)
              aggregate_key_type = try(tostring(r.statement.rate_based_statement.aggregate_key_type), "")
            }
          }
          visibility_config = {
            cloudwatch_metrics_enabled = try(tobool(r.visibility_config.cloudwatch_metrics_enabled), null)
            metric_name                = try(tostring(r.visibility_config.metric_name), null)
            sampled_requests_enabled   = try(tobool(r.visibility_config.sampled_requests_enabled), null)
          }
        }
      ]
      resource_arns = [for x in try([for x in f.resource_arns : x if !can(keys(f.resource_arns))], []) : try(tostring(x), "")]
    }
  }

  load_balancer_lookups = toset(flatten([for acl in local.web_acls : [for r in acl.resource_arns : r if r != "" && !startswith(r, "arn:")]]))

  resource_arns = { for name, acl in local.web_acls : name => [for lb in acl.resource_arns : startswith(lb, "arn:") ? lb : try(data.aws_lb.load_balancers[lb].arn, lb)] }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a web ACL's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_wafv2_web_acl takes them${var.scope == "REGIONAL" ? " (resource_arns: the load balancers it protects)" : "; a distribution names its web ACL with web_acl_id"}" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, f in local.files : "${name}.yml: default_action is allow or block" if !can(keys(f.default_action)) || try(length(keys(f.default_action)) != 1 || !contains(local.blocks.default_action, keys(f.default_action)[0]), true)],
    [for name, f in local.files : "${name}.yml: visibility_config takes ${join(", ", local.visibility_keys)}, all three" if !can(keys(f.visibility_config)) || try(jsonencode(sort(keys(f.visibility_config))) != jsonencode(sort(local.visibility_keys)), true)],
    [for name, f in local.files : "${name}.yml: rule is a list of rules" if try(f.rule, null) != null && (can(keys(f.rule)) || !can([for r in f.rule : r]))],
    [for name, f in local.files : "${name}.yml: resource_arns is a list of load balancers" if try(f.resource_arns, null) != null && (can(keys(f.resource_arns)) || !can([for r in f.resource_arns : r]))],
    flatten([for name, rules in local.rules : [
      for r in rules : "${name}.yml: a rule takes the arguments of aws_wafv2_web_acl's rule: ${join(", ", local.rule_keys)}" if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)])
    ]]),
    flatten([for name, rules in local.rules : [
      for r in rules : "${name}.yml: the rule ${try(tostring(r.name), "?")} needs name, priority and visibility_config (${join(", ", local.visibility_keys)})" if !can(tostring(r.name)) || !can(tonumber(r.priority)) || try(jsonencode(sort(keys(r.visibility_config))) != jsonencode(sort(local.visibility_keys)), true)
    ]]),
    flatten([for name, rules in local.rules : [
      for r in rules : "${name}.yml: statement in the rule ${try(tostring(r.name), "?")} is managed_rule_group_statement (${join(", ", local.managed_keys)}) or rate_based_statement (${join(", ", local.rate_keys)})"
      if try(length(keys(r.statement)) != 1, true) || !alltrue([for k in try(keys(r.statement), []) : contains(local.statement_keys, k) && try(jsonencode(sort(keys(r.statement[k]))) == jsonencode(sort(k == "rate_based_statement" ? local.rate_keys : local.managed_keys)), false)])
    ]]),
    flatten([for name, rules in local.rules : [
      for r in rules : "${name}.yml: action in the rule ${try(tostring(r.name), "?")} is ${join(", ", local.blocks.action)}; override_action is ${join(", ", local.blocks.override_action)}"
      if anytrue([for b in ["action", "override_action"] : try(r[b], null) != null && (!can(keys(r[b])) || !alltrue([for k in try(keys(r[b]), []) : contains(local.blocks[b], k)]))])
    ]]),
  )
}
