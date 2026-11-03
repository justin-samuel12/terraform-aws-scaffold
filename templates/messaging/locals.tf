locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => merge({}, try(yamldecode(file("${local.config_dir}/${name}")), {})) }

  file_keys         = ["queue", "topic"]
  queue_keys        = ["fifo_queue", "content_based_deduplication", "visibility_timeout_seconds", "message_retention_seconds", "delay_seconds", "receive_wait_time_seconds", "dead_letter", "senders", "consumers"]
  topic_keys        = ["fifo_topic", "content_based_deduplication", "subscriptions", "publishers"]
  subscription_keys = ["protocol", "endpoint", "raw_message_delivery", "filter_policy", "filter_policy_scope"]
  services          = ["cloudwatch", "events", "s3"]

  queues = { for name, f in local.files : name => merge({}, f.queue) if can(f.queue) }
  topics = { for name, f in local.files : name => merge({}, f.topic) if can(f.topic) }

  # Named <environment>-<file>, so the queue and the topic from one file share a name; ARNs are built from names, so a
  # topic and the queue it delivers into can refer to each other in one plan.
  account_id = data.aws_caller_identity.current.account_id
  arn_prefix = "arn:${data.aws_partition.current.partition}"
  queue_arns = { for name, q in local.queues : name => "${local.arn_prefix}:sqs:${var.region}:${local.account_id}:${var.environment}-${name}${try(q.fifo_queue, false) ? ".fifo" : ""}" }
  topic_arns = { for name, t in local.topics : name => "${local.arn_prefix}:sns:${var.region}:${local.account_id}:${var.environment}-${name}${try(t.fifo_topic, false) ? ".fifo" : ""}" }

  # queue:<file> names a queue in this stack; anything else is used as it is (an ARN, a URL, an address). A Lambda function
  # subscribes itself, from its own file (sns_topic_subscription), so this stack never waits for the lambda stack.
  subscriptions = {
    for name, t in local.topics : name => {
      for s in try(t.subscriptions, []) : try(s.endpoint, "?") => {
        protocol             = try(s.protocol, "?")
        endpoint             = startswith(try(s.endpoint, ""), "queue:") ? lookup(local.queue_arns, trimprefix(s.endpoint, "queue:"), s.endpoint) : try(s.endpoint, "?")
        raw_message_delivery = try(s.raw_message_delivery, false)
        filter_policy        = can(s.filter_policy) ? jsonencode(s.filter_policy) : null
        filter_policy_scope  = try(s.filter_policy_scope, null)
      }
    }
  }

  # Which of this stack's topics deliver into each queue.
  delivering_topics = { for name in keys(local.queues) : name => toset([for topic, subs in local.subscriptions : local.topic_arns[topic] if contains(keys(subs), "queue:${name}")]) }

  # Other environments are named, and found through config/; a 12-digit ID is used as it is. This account needs no policy:
  # its own IAM decides.
  references = flatten([
    [for name, q in local.queues : [for k in ["senders", "consumers"] : [for e in try(tolist(q[k]), []) : { file = name, entry = tostring(e) }]]],
    [for name, t in local.topics : [for e in try(tolist(t.publishers), []) : { file = name, entry = tostring(e) }]],
  ])

  environment_accounts = module.ip_plan.accounts.environments
  account_of           = { for e in distinct([for r in local.references : r.entry]) : e => can(regex("^[0-9]{12}$", e)) ? e : lookup(local.environment_accounts, e, "") }
  other_accounts = { for name, f in local.files : name => {
    senders    = toset([for e in try(tolist(f.queue.senders), []) : local.account_of[tostring(e)] if !contains(["", local.account_id], local.account_of[tostring(e)])])
    consumers  = toset([for e in try(tolist(f.queue.consumers), []) : local.account_of[tostring(e)] if !contains(["", local.account_id], local.account_of[tostring(e)])])
    publishers = toset([for e in try(tolist(f.topic.publishers), []) : local.account_of[tostring(e)] if !contains(["", local.account_id], local.account_of[tostring(e)])])
  } }
  publisher_services = { for name, t in local.topics : name => toset([for e in try(tolist(t.publishers), []) : tostring(e) if contains(local.services, tostring(e))]) }

  problems = concat(
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}" if length(f) == 0 || !alltrue([for k in keys(f) : contains(local.file_keys, k)])],
    [for name, q in local.queues : "${name}.yml: queue keys are ${join(", ", local.queue_keys)}" if !alltrue([for k in keys(q) : contains(local.queue_keys, k)])],
    [for name, t in local.topics : "${name}.yml: topic keys are ${join(", ", local.topic_keys)}" if !alltrue([for k in keys(t) : contains(local.topic_keys, k)])],
    [for name, t in local.topics : "${name}.yml: subscription keys are ${join(", ", local.subscription_keys)}, and each needs protocol and endpoint" if !alltrue([for s in try(t.subscriptions, []) : can(s.protocol) && can(s.endpoint) && alltrue([for k in keys(s) : contains(local.subscription_keys, k)])])],
    [for name, t in local.topics : "${name}.yml: two subscriptions to the same endpoint" if length(try(t.subscriptions, [])) != length(local.subscriptions[name])],
    flatten([for name, t in local.topics : [for s in try(t.subscriptions, []) : "${name}.yml: ${s.endpoint} names no queue in this stack" if startswith(try(s.endpoint, ""), "queue:") && !contains(keys(local.queues), trimprefix(s.endpoint, "queue:"))]]),
    flatten([for name, t in local.topics : [for s in try(t.subscriptions, []) : "${name}.yml: ${s.endpoint} is subscribed as ${try(s.protocol, "?")}; a queue: is subscribed as sqs" if startswith(try(s.endpoint, ""), "queue:") && try(s.protocol, "") != "sqs"]]),
    flatten([for name, t in local.topics : [for s in try(t.subscriptions, []) : "${name}.yml: a Lambda function subscribes itself, from its own file in the lambda stack (sns_topic_subscription: topic:${name}), so the two stacks never wait for each other" if try(s.protocol, "") == "lambda" || startswith(try(s.endpoint, ""), "lambda:")]]),
    flatten([for name, t in local.topics : [for s in try(t.subscriptions, []) : "${name}.yml: a FIFO topic delivers only to FIFO queues, and ${s.endpoint} is not one" if try(t.fifo_topic, false) && !(startswith(try(s.endpoint, ""), "queue:") && try(local.queues[trimprefix(s.endpoint, "queue:")].fifo_queue, false))]]),
    [for name, q in local.queues : "${name}.yml: dead_letter takes max_receive_count only" if can(q.dead_letter) && !alltrue([for k in try(keys(q.dead_letter), ["?"]) : k == "max_receive_count"])],
    [for r in local.references : "${r.file}.yml: ${r.entry} is not an environment in config/, a 12-digit account ID, or one of ${join(", ", local.services)}" if !can(regex("^[0-9]{12}$", r.entry)) && !contains(local.services, r.entry) && !contains(keys(local.environment_accounts), r.entry)],
    [for r in local.references : "${r.file}.yml: ${r.entry} has no account in config/ yet" if contains(keys(local.environment_accounts), r.entry) && lookup(local.environment_accounts, r.entry, "") == ""],
    [for name, q in local.queues : "${name}.yml: ${join(", ", [for e in concat(try(tolist(q.senders), []), try(tolist(q.consumers), [])) : tostring(e) if contains(local.services, tostring(e))])} cannot send to or read a queue directly; publish to a topic that delivers into it" if anytrue([for e in concat(try(tolist(q.senders), []), try(tolist(q.consumers), [])) : contains(local.services, tostring(e))])],
  )
}
