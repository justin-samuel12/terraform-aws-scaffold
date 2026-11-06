locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }

  file_keys = ["tags", "object_lock_enabled", "object_lock_configuration", "lifecycle_configuration", "cors_rule"]
  rule_keys = ["id", "status", "filter", "expiration", "noncurrent_version_expiration", "abort_incomplete_multipart_upload"]
  cors_keys = ["id", "allowed_methods", "allowed_origins", "allowed_headers", "expose_headers", "max_age_seconds"]

  account_id = data.aws_caller_identity.current.account_id
  names      = { for name in keys(local.files) : name => "${var.environment}-${name}-${local.account_id}-${var.region}" }

  rules = {
    for name, f in local.files : name => try(f.lifecycle_configuration.rule, null) == null ? [] : try(tolist(f.lifecycle_configuration.rule), [])
  }
  cors = {
    for name, f in local.files : name => try(f.cors_rule, null) == null ? [] : try(tolist(f.cors_rule), [])
  }

  buckets = {
    for name, f in local.files : name => {
      tags                = try(tomap(f.tags), {})
      object_lock_enabled = try(tobool(f.object_lock_enabled), false)
      object_lock_configuration = try(f.object_lock_configuration, null) == null ? null : {
        rule = {
          default_retention = {
            mode  = try(tostring(f.object_lock_configuration.rule.default_retention.mode), "")
            days  = try(tonumber(f.object_lock_configuration.rule.default_retention.days), null)
            years = try(tonumber(f.object_lock_configuration.rule.default_retention.years), null)
          }
        }
      }
      lifecycle_rule = [
        for r in local.rules[name] : {
          id                                = try(tostring(r.id), "")
          status                            = try(tostring(r.status), "")
          filter                            = try(r.filter, null) == null ? null : { prefix = try(tostring(r.filter.prefix), null) }
          expiration                        = try(r.expiration, null) == null ? null : { days = try(tonumber(r.expiration.days), null) }
          noncurrent_version_expiration     = try(r.noncurrent_version_expiration, null) == null ? null : { noncurrent_days = try(tonumber(r.noncurrent_version_expiration.noncurrent_days), null) }
          abort_incomplete_multipart_upload = try(r.abort_incomplete_multipart_upload, null) == null ? null : { days_after_initiation = try(tonumber(r.abort_incomplete_multipart_upload.days_after_initiation), null) }
        }
      ]
      cors_rule = [
        for c in local.cors[name] : {
          id              = try(tostring(c.id), null)
          allowed_methods = try([for m in tolist(c.allowed_methods) : tostring(m)], [])
          allowed_origins = try([for o in tolist(c.allowed_origins) : tostring(o)], [])
          allowed_headers = try(c.allowed_headers, null) == null ? null : try([for h in tolist(c.allowed_headers) : tostring(h)], [])
          expose_headers  = try(c.expose_headers, null) == null ? null : try([for h in tolist(c.expose_headers) : tostring(h)], [])
          max_age_seconds = try(tonumber(c.max_age_seconds), null)
        }
      ]
    }
  }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a bucket's name is built from its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_s3_bucket and its configuration resources take them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, bucket in local.names : "${name}.yml: ${bucket} is longer than S3's 63 characters; shorten the file name" if length(bucket) > 63],
    flatten([for name, rules in local.rules : [
      for r in rules : "${name}.yml: a lifecycle_configuration rule takes the arguments of aws_s3_bucket_lifecycle_configuration's rule: ${join(", ", local.rule_keys)}"
      if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)])
    ]]),
    [for name, f in local.files : "${name}.yml: lifecycle_configuration takes one key, rule, a list of rules" if try(f.lifecycle_configuration, null) != null && (!can(keys(f.lifecycle_configuration)) || jsonencode(try(keys(f.lifecycle_configuration), [])) != jsonencode(["rule"]) || !can(tolist(f.lifecycle_configuration.rule)))],
    flatten([for name, b in local.buckets : [
      for r in b.lifecycle_rule : "${name}.yml: every lifecycle rule needs id and status (Enabled or Disabled), and at least one of expiration.days, noncurrent_version_expiration.noncurrent_days or abort_incomplete_multipart_upload.days_after_initiation"
      if r.id == "" || !contains(["Enabled", "Disabled"], r.status) || try(r.expiration.days, null) == null && try(r.noncurrent_version_expiration.noncurrent_days, null) == null && try(r.abort_incomplete_multipart_upload.days_after_initiation, null) == null
    ]]),
    flatten([for name, rules in local.cors : [
      for c in rules : "${name}.yml: a cors_rule takes the arguments of aws_s3_bucket_cors_configuration's cors_rule: ${join(", ", local.cors_keys)}"
      if !can(keys(c)) || !alltrue([for k in try(keys(c), []) : contains(local.cors_keys, k)])
    ]]),
    flatten([for name, b in local.buckets : [for c in b.cors_rule : "${name}.yml: a cors_rule needs allowed_methods and allowed_origins, and its origins are named: * would let any website use the bucket from a visitor's browser" if length(c.allowed_methods) == 0 || length(c.allowed_origins) == 0 || contains(c.allowed_origins, "*")]]),
    [for name, b in local.buckets : "${name}.yml: object_lock_configuration needs object_lock_enabled: true" if b.object_lock_configuration != null && !b.object_lock_enabled],
    [for name, b in local.buckets : "${name}.yml: object_lock_configuration.rule.default_retention has mode GOVERNANCE or COMPLIANCE, and days or years" if b.object_lock_configuration != null && (!contains(["GOVERNANCE", "COMPLIANCE"], try(b.object_lock_configuration.rule.default_retention.mode, "")) || (try(b.object_lock_configuration.rule.default_retention.days, null) == null) == (try(b.object_lock_configuration.rule.default_retention.years, null) == null))],
  )
}
