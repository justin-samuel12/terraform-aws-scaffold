locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => merge({}, try(yamldecode(file("${local.config_dir}/${name}")), {})) }
  keys       = ["noncurrent_version_expiration", "expiration", "backup", "object_lock_configuration", "cors_rule"]

  # Named <environment>-<file>-<account>-<region>: unique, and telling at a glance whose bucket it is.
  account_id = data.aws_caller_identity.current.account_id
  names      = { for name in keys(local.files) : name => "${var.environment}-${name}-${local.account_id}-${var.region}" }

  problems = concat(
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.keys)}" if !alltrue([for k in keys(f) : contains(local.keys, k)])],
    [for name, bucket in local.names : "${name}.yml: ${bucket} is longer than S3's 63 characters; shorten the file name" if length(bucket) > 63],
  )
}
