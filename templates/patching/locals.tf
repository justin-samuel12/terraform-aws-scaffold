locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  paths      = [for p in fileset(local.config_dir, "**/*.yml") : p]
  folders    = ["patch-baseline", "maintenance-window"]
  in_kind    = { for p in local.paths : p => try([for f in local.folders : f if can(regex("(^|/)${f}/", p))][0], null) }
  found      = { for folder in local.folders : folder => { for p in local.paths : trimsuffix(basename(p), ".yml") => p... if local.in_kind[p] == folder } }
  read       = { for folder, names in local.found : folder => { for name, paths in names : name => try(merge({}, yamldecode(file("${local.config_dir}/${sort(paths)[0]}"))), "not a map") } }

  baseline_keys = ["description", "operating_system", "approved_patches", "rejected_patches", "approval_rule", "tags"]
  rule_keys     = ["approve_after_days", "compliance_level", "enable_non_security", "patch_filter"]
  window_keys   = ["description", "schedule", "schedule_timezone", "duration", "cutoff", "enabled", "tags"]
  baselines     = local.read["patch-baseline"]
  windows       = local.read["maintenance-window"]

  problems = concat(
    [for p in local.paths : "${p}: files go in patch-baseline/ or maintenance-window/" if local.in_kind[p] == null],
    flatten([for folder, names in local.found : [for name, paths in names : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a file's name is what it builds, so it must be unique" if length(paths) > 1]]),
    [for name, f in local.baselines : "patch-baseline/${name}.yml: keys are ${join(", ", local.baseline_keys)}, as aws_ssm_patch_baseline takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.baseline_keys, k)])],
    [for name, f in local.baselines : "patch-baseline/${name}.yml: needs operating_system" if !can(tostring(f.operating_system))],
    flatten([for name, f in local.baselines : [
      for r in try([for x in f.approval_rule : x], [null]) : "patch-baseline/${name}.yml: approval_rule is a list of rules, each with ${join(", ", local.rule_keys)}; patch_filter is a list of key and values"
      if can(f.approval_rule) && (!can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)]) || !alltrue([for p in try([for x in r.patch_filter : x], [null]) : try(keys(p) == ["key", "values"], false)]))
    ]]),
    [for os in distinct([for f in values(local.baselines) : try(tostring(f.operating_system), "")]) : "patch-baseline/: ${join(", ", sort([for name, f in local.baselines : "${name}.yml" if try(tostring(f.operating_system), "") == os]))} are all for ${os}; the patch group takes one baseline per operating system" if length([for f in values(local.baselines) : f if try(tostring(f.operating_system), "") == os]) > 1],
    [for name, f in local.windows : "maintenance-window/${name}.yml: keys are ${join(", ", local.window_keys)}, as aws_ssm_maintenance_window takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.window_keys, k)])],
    flatten([for name, f in local.windows : [for k in ["schedule", "duration", "cutoff"] : "maintenance-window/${name}.yml: needs ${k}" if !can(f[k])]]),
  )

  ready = length(local.problems) == 0
  patch_baselines = {
    for name, f in local.baselines : name => {
      description      = try(tostring(f.description), null)
      operating_system = try(tostring(f.operating_system), "")
      approved_patches = try(tolist(f.approved_patches), null)
      rejected_patches = try(tolist(f.rejected_patches), null)
      approval_rule = [
        for r in try([for x in f.approval_rule : x], []) : {
          approve_after_days  = try(tonumber(r.approve_after_days), null)
          compliance_level    = try(tostring(r.compliance_level), null)
          enable_non_security = try(tobool(r.enable_non_security), null)
          patch_filter        = [for p in try([for x in r.patch_filter : x], []) : { key = try(tostring(p.key), ""), values = try([for v in p.values : tostring(v)], []) }]
        }
      ]
      tags = try(tomap(f.tags), {})
    }
  }
  maintenance_windows = {
    for name, f in local.windows : name => {
      description       = try(tostring(f.description), null)
      schedule          = try(tostring(f.schedule), "")
      schedule_timezone = try(tostring(f.schedule_timezone), null)
      duration          = try(tonumber(f.duration), null)
      cutoff            = try(tonumber(f.cutoff), null)
      enabled           = try(tobool(f.enabled), null)
      tags              = try(tomap(f.tags), {})
    }
  }
}
