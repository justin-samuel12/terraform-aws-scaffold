locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  paths      = [for p in fileset(local.config_dir, "**/*.yml") : p]
  folders    = ["document", "log-group"]
  in_kind    = { for p in local.paths : p => try([for f in local.folders : f if can(regex("(^|/)${f}/", p))][0], null) }
  found      = { for folder in local.folders : folder => { for p in local.paths : trimsuffix(basename(p), ".yml") => p... if local.in_kind[p] == folder } }
  read       = { for folder, names in local.found : folder => { for name, paths in names : name => try(merge({}, yamldecode(file("${local.config_dir}/${sort(paths)[0]}"))), "not a map") } }

  document_name = "SSM-SessionManagerRunShell"
  log_group     = "sessions"
  document_keys = ["content", "tags"]
  input_keys    = ["idleSessionTimeout", "maxSessionDuration"]
  log_keys      = ["retention_in_days", "tags"]
  documents     = local.read.document
  log_groups    = local.read["log-group"]

  problems = concat(
    [for p in local.paths : "${p}: files go in document/ or log-group/" if local.in_kind[p] == null],
    flatten([for folder, names in local.found : [for name, paths in names : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a file's name is what it builds, so it must be unique" if length(paths) > 1]]),
    [for name, f in local.documents : "document/${name}.yml: Session Manager reads its preferences from one document, ${local.document_name}" if name != local.document_name],
    [for name, f in local.documents : "document/${name}.yml: keys are ${join(", ", local.document_keys)}; content takes inputs, which takes ${join(", ", local.input_keys)} (the key, the log group and streaming are fixed)" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.document_keys, k)]) || try(keys(f.content), []) != ["inputs"] || try(toset(keys(f.content.inputs)), toset([])) != toset(local.input_keys)],
    [for name, f in local.log_groups : "log-group/${name}.yml: the one log group here is ${local.log_group}, /ssm/sessions, where every session streams" if name != local.log_group],
    [for name, f in local.log_groups : "log-group/${name}.yml: keys are ${join(", ", local.log_keys)}, as aws_cloudwatch_log_group takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.log_keys, k)])],
    length(local.documents) > 0 && !contains(keys(local.log_groups), local.log_group) ? ["document/${local.document_name}.yml streams every session to /ssm/sessions: add log-group/${local.log_group}.yml"] : [],
  )

  ready = length(local.problems) == 0
  document = !contains(keys(local.documents), local.document_name) ? null : {
    content = { inputs = { for k in local.input_keys : k => try(tostring(local.documents[local.document_name].content.inputs[k]), "") } }
    tags    = try(tomap(local.documents[local.document_name].tags), {})
  }
  log_group_args = !contains(keys(local.log_groups), local.log_group) ? null : {
    retention_in_days = try(tonumber(local.log_groups[local.log_group].retention_in_days), null)
    tags              = try(tomap(local.log_groups[local.log_group].tags), {})
  }
}
