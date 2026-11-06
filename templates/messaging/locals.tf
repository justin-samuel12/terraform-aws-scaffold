locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  kinds      = ["queue", "topic"]
  paths      = [for path in fileset(local.config_dir, "**/*.yml") : path if !startswith(path, "src/")]
  found      = { for path in local.paths : "${split("/", path)[0]}/${trimsuffix(basename(path), ".yml")}" => path... if length(split("/", path)) > 1 && contains(local.kinds, split("/", path)[0]) }
  files      = { for key, paths in local.found : key => try(yamldecode(file("${local.config_dir}/${sort(paths)[0]}")), null) }
  queues     = { for key, f in local.files : trimprefix(key, "queue/") => f if startswith(key, "queue/") }
  topics     = { for key, f in local.files : trimprefix(key, "topic/") => f if startswith(key, "topic/") }

  queue_keys        = ["fifo_queue", "content_based_deduplication", "visibility_timeout_seconds", "message_retention_seconds", "delay_seconds", "receive_wait_time_seconds", "redrive_policy", "redrive_allow_policy", "policy"]
  topic_keys        = ["fifo_topic", "content_based_deduplication", "policy", "sns_topic_subscription"]
  subscription_keys = ["protocol", "endpoint", "raw_message_delivery", "filter_policy", "filter_policy_scope"]
  statement_keys    = ["effect", "actions", "resources", "principals", "condition"]
  account_variables = ["aws:SourceAccount", "aws:PrincipalAccount"]

  account_id  = data.aws_caller_identity.current.account_id
  arn_prefix  = "arn:${data.aws_partition.current.partition}"
  accounts    = module.ip_plan.accounts.environments
  queue_names = { for name, f in local.queues : name => "${var.environment}-${name}${try(tobool(f.fifo_queue), false) ? ".fifo" : ""}" }
  topic_names = { for name, f in local.topics : name => "${var.environment}-${name}${try(tobool(f.fifo_topic), false) ? ".fifo" : ""}" }
  queue_arns  = { for name, full in local.queue_names : name => "${local.arn_prefix}:sqs:${var.region}:${local.account_id}:${full}" }
  topic_arns  = { for name, full in local.topic_names : name => "${local.arn_prefix}:sns:${var.region}:${local.account_id}:${full}" }

  written = flatten([for key, f in local.files : [
    for s in try(concat(f.policy.statement, []), []) : { file = "${key}.yml", kind = split("/", key)[0], s = s }
  ]])

  statements = {
    for kind in local.kinds : kind => {
      for key, f in local.files : split("/", key)[1] => [
        for s in try(concat(f.policy.statement, []), []) : {
          effect    = try(tostring(s.effect), "Allow")
          actions   = [for a in try(concat(s.actions, []), []) : tostring(a)]
          resources = [for r in try(concat(s.resources, []), []) : lookup(kind == "queue" ? local.queue_arns : local.topic_arns, tostring(r), tostring(r))]
          principals = [for p in try(concat(s.principals, []), []) : {
            type        = try(tostring(p.type), "")
            identifiers = [for i in try(concat(p.identifiers, []), []) : try(p.type, "") == "AWS" && lookup(local.accounts, tostring(i), "") != "" ? "${local.arn_prefix}:iam::${local.accounts[tostring(i)]}:root" : tostring(i)]
          }]
          condition = [for c in try(concat(s.condition, []), []) : {
            test     = try(tostring(c.test), "")
            variable = try(tostring(c.variable), "")
            values   = [for v in try(concat(c.values, []), []) : contains(local.account_variables, try(tostring(c.variable), "")) && lookup(local.accounts, tostring(v), "") != "" ? local.accounts[tostring(v)] : try(c.variable, "") == "aws:SourceArn" ? lookup(local.topic_arns, tostring(v), tostring(v)) : tostring(v)]
          }]
        }
      ] if split("/", key)[0] == kind
    }
  }

  subscriptions = {
    for name, f in local.topics : name => {
      for s in try(concat(f.sns_topic_subscription, []), []) : try(tostring(s.endpoint), "?") => {
        protocol             = try(tostring(s.protocol), "?")
        endpoint             = try(s.protocol, "") == "sqs" ? lookup(local.queue_arns, try(tostring(s.endpoint), ""), try(tostring(s.endpoint), "?")) : try(tostring(s.endpoint), "?")
        raw_message_delivery = try(tobool(s.raw_message_delivery), null)
        filter_policy        = can(s.filter_policy) ? jsonencode(s.filter_policy) : null
        filter_policy_scope  = try(tostring(s.filter_policy_scope), null)
      }
    }
  }
  subscribed = flatten([for topic, f in local.topics : [for s in try(concat(f.sns_topic_subscription, []), []) : { topic = topic, protocol = try(tostring(s.protocol), ""), endpoint = try(tostring(s.endpoint), "") }]])

  queue_targets = flatten([for name, f in local.queues : concat(
    can(f.redrive_policy.dead_letter_target_arn) ? [{ file = name, key = "redrive_policy.dead_letter_target_arn", target = tostring(f.redrive_policy.dead_letter_target_arn) }] : [],
    [for q in try(concat(f.redrive_allow_policy.source_queue_arns, []), []) : { file = name, key = "redrive_allow_policy.source_queue_arns", target = tostring(q) }],
  )])

  is_arn = "^(arn:|\\*$)"

  problems = concat(
    [for key, paths in local.found : "${key}.yml is in more than one folder (${join(", ", sort(paths))}); a ${split("/", key)[0]}'s name is its file's, so it must be unique" if length(paths) > 1],
    [for path in local.paths : "${path}: a file belongs in queue/ (an aws_sqs_queue) or topic/ (an aws_sns_topic)" if length(split("/", path)) == 1 || !contains(local.kinds, split("/", path)[0])],
    [for name, f in local.queues : "queue/${name}.yml: keys are ${join(", ", local.queue_keys)}, as aws_sqs_queue takes them" if f != null && !alltrue([for k in try(keys(f), ["?"]) : contains(local.queue_keys, k)])],
    [for name, f in local.topics : "topic/${name}.yml: keys are ${join(", ", local.topic_keys)}, as aws_sns_topic takes them" if f != null && !alltrue([for k in try(keys(f), ["?"]) : contains(local.topic_keys, k)])],
    [for key, f in local.files : "${key}.yml: policy holds a statement list, as aws_iam_policy_document writes it" if can(f.policy) && !(can(concat(f.policy.statement, [])) && length(try(keys(f.policy), [])) == 1)],
    [for w in local.written : "${w.file}: a statement takes ${join(", ", local.statement_keys)}, as aws_iam_policy_document does" if !alltrue([for k in try(keys(w.s), ["?"]) : contains(local.statement_keys, k)])],
    [for w in local.written : "${w.file}: a statement needs actions and resources" if length(try(concat(w.s.actions, []), [])) == 0 || length(try(concat(w.s.resources, []), [])) == 0],
    [for w in local.written : "${w.file}: a principal takes type and identifiers; a condition takes test, variable and values" if !alltrue(concat([for p in try(concat(w.s.principals, []), []) : can(p.type) && can(concat(p.identifiers, [])) && try(length(keys(p)), 0) == 2], [for c in try(concat(w.s.condition, []), []) : can(c.test) && can(c.variable) && can(concat(c.values, [])) && try(length(keys(c)), 0) == 3]))],
    flatten([for w in local.written : [for r in try(concat(w.s.resources, []), []) : "${w.file}: resource ${r} is not a ${w.kind} in this stack (a file named ${w.kind}/${r}.yml) or an ARN" if !can(regex(local.is_arn, tostring(r))) && !contains(keys(local.files), "${w.kind}/${r}")]]),
    flatten([for w in local.written : [for p in try(concat(w.s.principals, []), []) : [for i in try(concat(p.identifiers, []), []) : "${w.file}: the AWS principal ${i} is not an environment in config/, a 12-digit account ID or an ARN" if try(p.type, "") == "AWS" && !can(regex("^([0-9]{12}|arn:.*|\\*)$", tostring(i))) && !contains(keys(local.accounts), tostring(i))]]]),
    flatten([for w in local.written : [for c in try(concat(w.s.condition, []), []) : [for v in try(concat(c.values, []), []) : "${w.file}: ${c.variable} ${v} is not an environment in config/ or a 12-digit account ID" if contains(local.account_variables, try(tostring(c.variable), "")) && !can(regex("^[0-9]{12}$", tostring(v))) && !contains(keys(local.accounts), tostring(v))]]]),
    flatten([for w in local.written : [for c in try(concat(w.s.condition, []), []) : [for v in try(concat(c.values, []), []) : "${w.file}: aws:SourceArn ${v} is not a topic in this stack (a file named topic/${v}.yml) or an ARN" if try(c.variable, "") == "aws:SourceArn" && !can(regex(local.is_arn, tostring(v))) && !contains(keys(local.topics), tostring(v))]]]),
    distinct(flatten([for w in local.written : concat(
      [for p in try(concat(w.s.principals, []), []) : [for i in try(concat(p.identifiers, []), []) : "${w.file}: ${i} has no account in config/ yet" if try(p.type, "") == "AWS" && contains(keys(local.accounts), tostring(i)) && lookup(local.accounts, tostring(i), "") == ""]],
      [for c in try(concat(w.s.condition, []), []) : [for v in try(concat(c.values, []), []) : "${w.file}: ${v} has no account in config/ yet" if contains(local.account_variables, try(tostring(c.variable), "")) && contains(keys(local.accounts), tostring(v)) && lookup(local.accounts, tostring(v), "") == ""]],
    )])),
    [for name, f in local.queues : "queue/${name}.yml: redrive_policy takes dead_letter_target_arn and max_receive_count" if can(f.redrive_policy) && !(can(f.redrive_policy.dead_letter_target_arn) && can(tonumber(f.redrive_policy.max_receive_count)) && length(try(keys(f.redrive_policy), [])) == 2)],
    [for name, f in local.queues : "queue/${name}.yml: redrive_allow_policy takes redrive_permission, and source_queue_arns for byQueue" if can(f.redrive_allow_policy) && !(can(f.redrive_allow_policy.redrive_permission) && alltrue([for k in try(keys(f.redrive_allow_policy), ["?"]) : contains(["redrive_permission", "source_queue_arns"], k)]))],
    [for t in local.queue_targets : "queue/${t.file}.yml: ${t.key} ${t.target} is not a queue in this stack (a file named queue/${t.target}.yml) or an ARN" if !startswith(t.target, "arn:") && !contains(keys(local.queues), t.target)],
    [for t in local.queue_targets : "queue/${t.file}.yml: ${t.key} ${t.target} is ${endswith(local.queue_names[t.target], ".fifo") ? "" : "not "}a FIFO queue, and ${t.file} is ${endswith(local.queue_names[t.file], ".fifo") ? "" : "not "}one; both must be the same" if contains(keys(local.queues), t.target) && endswith(lookup(local.queue_names, t.target, ""), ".fifo") != endswith(local.queue_names[t.file], ".fifo")],
    [for name, f in local.topics : "topic/${name}.yml: sns_topic_subscription is a list, each with protocol and endpoint, and keys ${join(", ", local.subscription_keys)}, as aws_sns_topic_subscription takes them" if can(f.sns_topic_subscription) && !(can(concat(f.sns_topic_subscription, [])) && alltrue([for s in try(concat(f.sns_topic_subscription, []), []) : can(s.protocol) && can(s.endpoint) && alltrue([for k in try(keys(s), ["?"]) : contains(local.subscription_keys, k)])]))],
    [for name, f in local.topics : "topic/${name}.yml: two subscriptions to the same endpoint" if length(try(concat(f.sns_topic_subscription, []), [])) != length(local.subscriptions[name])],
    [for s in local.subscribed : "topic/${s.topic}.yml: endpoint ${s.endpoint} is not a queue in this stack (a file named queue/${s.endpoint}.yml) or a queue's ARN" if s.protocol == "sqs" && !startswith(s.endpoint, "arn:") && !contains(keys(local.queues), s.endpoint)],
    [for s in local.subscribed : "topic/${s.topic}.yml: a Lambda function subscribes itself, from its own file in the lambda stack (sns_topic_subscription.topic_arn: ${s.topic}), so the two stacks never wait for each other" if s.protocol == "lambda"],
    [for s in local.subscribed : "topic/${s.topic}.yml: a FIFO topic delivers only to FIFO queues, and ${s.endpoint} is not one" if endswith(local.topic_names[s.topic], ".fifo") && !(s.protocol == "sqs" && endswith(lookup(local.queue_names, s.endpoint, s.endpoint), ".fifo"))],
    [for s in local.subscribed : "topic/${s.topic}.yml: queue/${s.endpoint}.yml has no policy statement letting sns.amazonaws.com send to it, so nothing the topic delivers would arrive" if s.protocol == "sqs" && contains(keys(local.queues), s.endpoint) && !anytrue([for st in lookup(local.statements.queue, s.endpoint, []) : anytrue([for p in st.principals : p.type == "Service" && contains(p.identifiers, "sns.amazonaws.com")])])],
  )

  sqs_queues = {
    for name, f in local.queues : local.queue_names[name] => {
      fifo_queue                  = try(tobool(f.fifo_queue), null)
      content_based_deduplication = try(tobool(f.content_based_deduplication), null)
      visibility_timeout_seconds  = try(tonumber(f.visibility_timeout_seconds), null)
      message_retention_seconds   = try(tonumber(f.message_retention_seconds), null)
      delay_seconds               = try(tonumber(f.delay_seconds), null)
      receive_wait_time_seconds   = try(tonumber(f.receive_wait_time_seconds), null)
      redrive_policy = can(f.redrive_policy) ? {
        dead_letter_target_arn = try(lookup(local.queue_arns, tostring(f.redrive_policy.dead_letter_target_arn), tostring(f.redrive_policy.dead_letter_target_arn)), "")
        max_receive_count      = try(tonumber(f.redrive_policy.max_receive_count), 0)
      } : null
      redrive_allow_policy = can(f.redrive_allow_policy) ? {
        redrive_permission = try(tostring(f.redrive_allow_policy.redrive_permission), "")
        source_queue_arns  = can(f.redrive_allow_policy.source_queue_arns) ? [for q in try(concat(f.redrive_allow_policy.source_queue_arns, []), []) : try(lookup(local.queue_arns, tostring(q), tostring(q)), "")] : null
      } : null
      policy_statements = local.statements.queue[name]
    }
  }
}
