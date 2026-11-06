locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  paths      = [for p in fileset(local.config_dir, "**/*.yml") : p]
  found      = { for p in local.paths : trimsuffix(basename(p), ".yml") => p... }
  files      = { for name, paths in local.found : name => try(merge({}, yamldecode(file("${local.config_dir}/${sort(paths)[0]}"))), "not a map") }

  delivers   = { lb-logs = "load-balancer", aws-waf-logs = "waf" }
  file_keys  = ["tags", "lifecycle_configuration"]
  rule_keys  = ["id", "status", "filter", "expiration", "noncurrent_version_expiration", "abort_incomplete_multipart_upload"]
  account_id = data.aws_caller_identity.current.account_id

  rules = {
    for name, f in local.files : name => [
      for r in try([for x in f.lifecycle_configuration.rule : x], []) : {
        id                                = try(tostring(r.id), "")
        status                            = try(tostring(r.status), "")
        filter                            = { prefix = try(tostring(r.filter.prefix), "") }
        expiration                        = can(r.expiration) ? { days = try(tonumber(r.expiration.days), null) } : null
        noncurrent_version_expiration     = can(r.noncurrent_version_expiration) ? { noncurrent_days = try(tonumber(r.noncurrent_version_expiration.noncurrent_days), null) } : null
        abort_incomplete_multipart_upload = can(r.abort_incomplete_multipart_upload) ? { days_after_initiation = try(tonumber(r.abort_incomplete_multipart_upload.days_after_initiation), null) } : null
      }
    ]
  }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a bucket's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: a log bucket is lb-logs (load balancer access logs) or aws-waf-logs (WAF logs); its delivery policy is fixed by which it is" if !contains(keys(local.delivers), name)],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_s3_bucket and aws_s3_bucket_lifecycle_configuration take them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, f in local.files : "${name}.yml: lifecycle_configuration takes rule, a list of rules" if can(f.lifecycle_configuration) && !(try(keys(f.lifecycle_configuration), []) == ["rule"] && (can([for x in f.lifecycle_configuration.rule : x]) && !can(keys(f.lifecycle_configuration.rule))))],
    flatten([for name, f in local.files : [
      for r in try([for x in f.lifecycle_configuration.rule : x], []) : "${name}.yml: a lifecycle rule takes ${join(", ", local.rule_keys)}, and needs id and status" if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)]) || !can(tostring(r.id)) || !can(tostring(r.status))
    ]]),
  )

  ready = length(local.problems) == 0
  buckets = {
    for name, f in local.files : name => {
      bucket   = "${name}-${local.account_id}-${var.region}"
      delivers = lookup(local.delivers, name, "")
      tags     = try(tomap(f.tags), {})
      rule     = local.rules[name]
    }
  }
}
