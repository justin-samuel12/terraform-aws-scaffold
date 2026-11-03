locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  keys       = ["runtime", "handler", "memory_size", "timeout", "environment", "statement", "schedule_expression", "retention_in_days", "event_source_mapping"]

  problems = concat(
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.keys)}" if !alltrue([for k in try(keys(f), []) : contains(local.keys, k)])],
    [for name, f in local.files : "${name}.yml: needs runtime and handler" if !can(f.runtime) || !can(f.handler)],
    [for name, f in local.files : "${name}.yml: environment holds variables, as in the AWS provider: environment: { variables: { NAME: value } }" if can(f.environment) && !alltrue([for k in try(keys(f.environment), ["?"]) : k == "variables"])],
    [for name in keys(local.files) : "${name}.yml: its code belongs in src/${name}/, which is empty or missing" if length(fileset("${local.config_dir}/src/${name}", "**")) == 0],
    [for name, f in local.files : "${name}.yml: event_source_mapping takes event_source_arn (queue:<name>, or a queue's ARN), batch_size and maximum_batching_window_in_seconds" if can(f.event_source_mapping) && !(can(f.event_source_mapping.event_source_arn) && alltrue([for k in try(keys(f.event_source_mapping), ["?"]) : contains(["event_source_arn", "batch_size", "maximum_batching_window_in_seconds"], k)]))],
  )

  # queue:<name> is this environment's queue from the messaging stack, <environment>-<name> (with .fifo for a FIFO queue).
  queue_names = { for name, f in local.files : name => "${var.environment}-${trimprefix(f.event_source_mapping.event_source_arn, "queue:")}" if startswith(try(f.event_source_mapping.event_source_arn, ""), "queue:") }
}
