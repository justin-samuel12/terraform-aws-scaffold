locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  paths      = [for p in fileset(local.config_dir, "**/*.yml") : p]
  in_kind    = { for p in local.paths : p => can(regex("(^|/)replication-configuration/", p)) ? "replication-configuration" : "repository" }
  found      = { for kind in ["repository", "replication-configuration"] : kind => { for p in local.paths : trimsuffix(basename(p), ".yml") => p... if local.in_kind[p] == kind } }
  read       = { for folder, names in local.found : folder => { for name, paths in names : name => try(yamldecode(file("${local.config_dir}/${sort(paths)[0]}")), null) } }

  repository_keys  = ["tags", "lifecycle_policy", "repository_policy"]
  replication_keys = ["replication_configuration"]
  rule_keys        = ["destination", "repository_filter"]
  repositories     = { for name, f in local.read.repository : name => try(merge({}, f), f) }
  replications     = local.read["replication-configuration"]

  accounts   = merge({ for env, account in module.ip_plan.accounts.environments : env => account if account != "" }, try(module.ip_plan.accounts.hubs[var.region], "") == "" ? {} : { shared = module.ip_plan.accounts.hubs[var.region] })
  principals = { for name, account in local.accounts : name => "arn:${data.aws_partition.current.partition}:iam::${account}:root" }
  as_account = "^([0-9]{12}|arn:.+|\\*)$"

  statements = {
    for name, f in local.repositories : name => [
      for s in try([for x in f.repository_policy.policy.Statement : x], []) : merge(s, can(s.Principal.AWS) ? {
        Principal = merge(s.Principal, { AWS = [for p in flatten([s.Principal.AWS]) : lookup(local.principals, p, p)] })
      } : {})
    ]
  }
  principal_names = flatten([for name, f in local.repositories : [for s in try([for x in f.repository_policy.policy.Statement : x], []) : [for p in try(flatten([s.Principal.AWS]), []) : { file = name, name = tostring(p) }]]])

  replication_file = length(local.replications) == 1 ? values(local.replications)[0] : null
  replication = local.replication_file == null ? null : {
    rule = [
      for r in try([for x in local.replication_file.replication_configuration.rule : x], []) : {
        destination       = [for d in try([for x in r.destination : x], []) : { region = try(tostring(d.region), ""), registry_id = lookup(local.accounts, try(tostring(d.registry_id), ""), try(tostring(d.registry_id), "")) }]
        repository_filter = [for x in try([for x in r.repository_filter : x], []) : { filter = try(tostring(x.filter), ""), filter_type = try(tostring(x.filter_type), "") }]
      }
    ]
  }

  problems = concat(
    flatten([for folder, names in local.found : [for name, paths in names : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a file's name is what it builds, so it must be unique" if length(paths) > 1]]),
    [for name, f in local.repositories : "${name}.yml: keys are ${join(", ", local.repository_keys)}: the repository's tags, and the policy of its aws_ecr_lifecycle_policy and aws_ecr_repository_policy" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.repository_keys, k)])],
    flatten([for name, f in local.repositories : [
      for k in ["lifecycle_policy", "repository_policy"] : "${name}.yml: ${k} takes policy, the policy document written as YAML" if can(f[k]) && !(try(keys(f[k]), []) == ["policy"] && can(keys(f[k].policy)))
    ]]),
    [for p in local.principal_names : "${p.file}.yml: Principal AWS ${p.name} is not an account ID, an ARN, or an environment in config/ with an account_id (${join(", ", sort(keys(local.accounts)))})" if !can(regex(local.as_account, p.name)) && !contains(keys(local.accounts), p.name)],
    length(local.replications) > 1 ? ["replication-configuration/: the registry has one replication configuration; found ${join(", ", sort(keys(local.replications)))}"] : [],
    [for name, f in local.replications : "replication-configuration/${name}.yml: keys are ${join(", ", local.replication_keys)}, as aws_ecr_replication_configuration takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.replication_keys, k)])],
    flatten([for name, f in local.replications : [
      for r in try([for x in f.replication_configuration.rule : x], [null]) : "replication-configuration/${name}.yml: replication_configuration.rule is a list of rules, each with ${join(", ", local.rule_keys)}; destination is a list of region and registry_id" if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)]) || !(can([for x in r.destination : x]) && !can(keys(r.destination)))
    ]]),
    flatten([for name, f in local.replications : [
      for r in try([for x in f.replication_configuration.rule : x], []) : [
        for d in try([for x in r.destination : x], []) : "replication-configuration/${name}.yml: registry_id ${try(tostring(d.registry_id), "")} is not an account ID or an environment in config/ with an account_id (${join(", ", sort(keys(local.accounts)))})"
        if !can(regex("^[0-9]{12}$", try(tostring(d.registry_id), ""))) && !contains(keys(local.accounts), try(tostring(d.registry_id), ""))
      ]
    ]]),
  )

  ready = length(local.problems) == 0
  built = {
    for name, f in local.repositories : name => {
      tags              = try(tomap(f.tags), {})
      lifecycle_policy  = can(f.lifecycle_policy) ? jsonencode(f.lifecycle_policy.policy) : null
      repository_policy = can(f.repository_policy) ? jsonencode(merge(f.repository_policy.policy, { Statement = local.statements[name] })) : null
    }
  }
}
