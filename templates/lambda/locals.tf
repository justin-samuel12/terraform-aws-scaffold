locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found      = { for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path... if !startswith(path, "src/") }
  files      = { for name, paths in local.found : name => try(yamldecode(file("${local.config_dir}/${sort(paths)[0]}")), null) }

  file_keys         = ["runtime", "handler", "memory_size", "timeout", "architectures", "layers", "vpc_config", "environment", "statement", "cloudwatch_event_rule", "cloudwatch_log_group", "event_source_mapping", "sns_topic_subscription"]
  rule_keys         = ["schedule_expression", "event_pattern"]
  vpc_config_keys   = ["subnet_ids", "security_group_ids"]
  statement_keys    = ["effect", "actions", "resources", "condition"]
  mapping_keys      = ["event_source_arn", "batch_size", "maximum_batching_window_in_seconds", "function_response_types"]
  subscription_keys = ["topic_arn", "filter_policy", "filter_policy_scope"]

  statements = {
    for name, f in local.files : name => [
      for s in try(concat(f.statement, []), []) : {
        effect    = try(tostring(s.effect), "Allow")
        actions   = [for a in try(concat(s.actions, []), []) : tostring(a)]
        resources = [for r in try(concat(s.resources, []), []) : tostring(r)]
        condition = [for c in try(concat(s.condition, []), []) : {
          test     = try(tostring(c.test), "")
          variable = try(tostring(c.variable), "")
          values   = [for v in try(concat(c.values, []), []) : tostring(v)]
        }]
      }
    ]
  }

  subscriptions = {
    for name, f in local.files : name => {
      for s in try(concat(f.sns_topic_subscription, []), []) : replace(try(tostring(s.topic_arn), "?"), "/^.*:/", "") => {
        topic               = startswith(try(tostring(s.topic_arn), "arn:"), "arn:") ? null : "${var.environment}-${s.topic_arn}"
        arn                 = startswith(try(tostring(s.topic_arn), "arn:"), "arn:") ? try(tostring(s.topic_arn), null) : null
        filter_policy       = can(s.filter_policy) ? jsonencode(s.filter_policy) : null
        filter_policy_scope = try(tostring(s.filter_policy_scope), null)
      }
    }
  }
  event_patterns = { for name, f in local.files : name => jsonencode(f.cloudwatch_event_rule.event_pattern) if can(f.cloudwatch_event_rule.event_pattern) }
  vpc_configs = {
    for name, f in local.files : name => {
      subnet_ids         = [for x in try(concat(f.vpc_config.subnet_ids, []), []) : tostring(x)]
      security_group_ids = [for x in try(concat(f.vpc_config.security_group_ids, []), []) : tostring(x)]
    } if can(f.vpc_config)
  }
  subnets     = toset(flatten([for c in values(local.vpc_configs) : [for s in c.subnet_ids : s if !startswith(s, "subnet-")]]))
  groups      = toset(flatten([for c in values(local.vpc_configs) : [for g in c.security_group_ids : g if !startswith(g, "sg-")]]))
  topic_names = toset(flatten([for name, subs in local.subscriptions : [for s in values(subs) : s.topic if s.topic != null]]))
  queue_names = { for name, f in local.files : name => "${var.environment}-${f.event_source_mapping.event_source_arn}" if can(tostring(f.event_source_mapping.event_source_arn)) && !startswith(try(tostring(f.event_source_mapping.event_source_arn), "arn:"), "arn:") }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a function's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}" if !alltrue([for k in try(keys(f), ["?"]) : contains(local.file_keys, k)])],
    [for name, f in local.files : "${name}.yml: needs runtime and handler, as aws_lambda_function does" if !can(tostring(f.runtime)) || !can(tostring(f.handler))],
    [for name, f in local.files : "${name}.yml: needs cloudwatch_log_group.retention_in_days, how long the function's logs are kept (365 unless there is a reason for another period)" if !can(tonumber(f.cloudwatch_log_group.retention_in_days)) || length(try(keys(f.cloudwatch_log_group), [])) != 1],
    [for name, f in local.files : "${name}.yml: cloudwatch_event_rule takes schedule_expression, event_pattern or both" if can(f.cloudwatch_event_rule) && !(length(try(keys(f.cloudwatch_event_rule), [])) > 0 && alltrue([for k in try(keys(f.cloudwatch_event_rule), []) : contains(local.rule_keys, k)]) && (!can(f.cloudwatch_event_rule.schedule_expression) || can(tostring(f.cloudwatch_event_rule.schedule_expression))) && (!can(f.cloudwatch_event_rule.event_pattern) || can(keys(f.cloudwatch_event_rule.event_pattern))))],
    [for name, f in local.files : "${name}.yml: architectures is a list of one, x86_64 or arm64" if can(f.architectures) && !(length(try(concat(f.architectures, []), [])) == 1 && alltrue([for a in try(concat(f.architectures, []), []) : contains(["x86_64", "arm64"], try(tostring(a), ""))]))],
    [for name, f in local.files : "${name}.yml: layers is a list of layer ARNs" if can(f.layers) && !alltrue([for l in try(concat(f.layers, []), ["?"]) : startswith(try(tostring(l), "?"), "arn:")])],
    [for name, f in local.files : "${name}.yml: vpc_config takes subnet_ids and security_group_ids, as aws_lambda_function does, and needs both" if can(f.vpc_config) && !(toset(try(keys(f.vpc_config), [])) == toset(local.vpc_config_keys) && length(try(concat(f.vpc_config.subnet_ids, []), [])) > 0 && length(try(concat(f.vpc_config.security_group_ids, []), [])) > 0)],
    [for name, f in local.files : "${name}.yml: environment holds variables, as in aws_lambda_function: environment.variables.NAME: value" if can(f.environment) && !alltrue([for k in try(keys(f.environment), ["?"]) : k == "variables"])],
    [for name in keys(local.files) : "${name}.yml: its code belongs in src/${name}/, which is empty or missing" if length(fileset("${local.config_dir}/src/${name}", "**")) == 0],
    [for name, f in local.files : "${name}.yml: statement is a list; each takes ${join(", ", local.statement_keys)}, as aws_iam_policy_document does, and needs actions and resources" if can(f.statement) && !(can(concat(f.statement, [])) && alltrue([for s in try(concat(f.statement, []), []) : length(try(concat(s.actions, []), [])) > 0 && length(try(concat(s.resources, []), [])) > 0 && alltrue([for k in try(keys(s), ["?"]) : contains(local.statement_keys, k)])]))],
    [for name, f in local.files : "${name}.yml: a statement's condition takes test, variable and values" if !alltrue(flatten([for s in try(concat(f.statement, []), []) : [for c in try(concat(s.condition, []), []) : can(tostring(c.test)) && can(tostring(c.variable)) && can(concat(c.values, [])) && try(length(keys(c)), 0) == 3]]))],
    [for name, f in local.files : "${name}.yml: sns_topic_subscription is a list; each takes ${join(", ", local.subscription_keys)}, with topic_arn a topic's name in this environment or its ARN" if can(f.sns_topic_subscription) && !(can(concat(f.sns_topic_subscription, [])) && alltrue([for s in try(concat(f.sns_topic_subscription, []), []) : can(tostring(s.topic_arn)) && alltrue([for k in try(keys(s), ["?"]) : contains(local.subscription_keys, k)])]))],
    [for name, f in local.files : "${name}.yml: event_source_mapping takes ${join(", ", local.mapping_keys)}, with event_source_arn a queue's name in this environment or its ARN" if can(f.event_source_mapping) && !(can(tostring(f.event_source_mapping.event_source_arn)) && alltrue([for k in try(keys(f.event_source_mapping), ["?"]) : contains(local.mapping_keys, k)]))],
  )
}
