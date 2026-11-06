locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found      = { for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path... }
  files      = { for name, paths in local.found : name => try(yamldecode(file("${local.config_dir}/${sort(paths)[0]}")), null) }
  file_keys  = ["targets", "parameters", "schedule_expression", "compliance_severity", "max_concurrency", "max_errors"]
  parameters = ["DomainName", "OrganizationalUnit"]

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); an association's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_ssm_association takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, f in local.files : "${name}.yml: parameters are ${join(" and ", local.parameters)}, both needed; SecretId is always the environment's join secret" if !can(keys(f.parameters)) || toset(try(keys(f.parameters), [])) != toset(local.parameters)],
    [for name, f in local.files : "${name}.yml: targets is a list of key (tag:<name>) and values, so only the servers carrying that tag join" if !can(tolist(f.targets)) || length(try(tolist(f.targets), [])) == 0 || !alltrue([for t in try(tolist(f.targets), []) : startswith(try(tostring(t.key), ""), "tag:") && length(try(tolist(t.values), [])) > 0])],
  )

  associations = length(local.problems) > 0 ? {} : {
    for name, f in local.files : name => {
      targets             = [for t in f.targets : { key = tostring(t.key), values = [for v in t.values : tostring(v)] }]
      parameters          = { for k in local.parameters : k => tostring(f.parameters[k]) }
      schedule_expression = try(tostring(f.schedule_expression), null)
      compliance_severity = try(tostring(f.compliance_severity), null)
      max_concurrency     = try(tostring(f.max_concurrency), null)
      max_errors          = try(tostring(f.max_errors), null)
    }
  }
}
