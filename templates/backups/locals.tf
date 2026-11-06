locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  paths      = [for p in fileset(local.config_dir, "**/*.yml") : p]
  folders    = ["backup-vault", "backup-plan"]
  in_kind    = { for p in local.paths : p => try([for f in local.folders : f if can(regex("(^|/)${f}/", p))][0], null) }
  found      = { for folder in local.folders : folder => { for p in local.paths : trimsuffix(basename(p), ".yml") => p... if local.in_kind[p] == folder } }
  read       = { for folder, names in local.found : folder => { for name, paths in names : name => try(merge({}, yamldecode(file("${local.config_dir}/${sort(paths)[0]}"))), "not a map") } }

  vault_keys     = ["region", "kms_key_arn", "lock_configuration", "tags"]
  lock_keys      = ["min_retention_days", "max_retention_days", "changeable_for_days"]
  plan_keys      = ["rule", "tags"]
  rule_keys      = ["rule_name", "target_vault_name", "schedule", "schedule_expression_timezone", "start_window", "completion_window", "enable_continuous_backup", "recovery_point_tags", "lifecycle", "copy_action"]
  lifecycle_keys = ["delete_after", "cold_storage_after"]
  regions        = distinct([for key in keys(module.ip_plan.networks) : split("/", key)[1]])

  vault_files = local.read["backup-vault"]
  plan_files  = local.read["backup-plan"]

  vaults = {
    for name, f in local.vault_files : name => {
      region      = try(tostring(f.region), null)
      kms_key_arn = try(tostring(f.kms_key_arn), "")
      tags        = try(tomap(f.tags), {})
      lock_configuration = {
        min_retention_days  = try(tonumber(f.lock_configuration.min_retention_days), 0)
        max_retention_days  = try(tonumber(f.lock_configuration.max_retention_days), null)
        changeable_for_days = try(tonumber(f.lock_configuration.changeable_for_days), null)
      }
    }
  }
  key_names = { for name, v in local.vaults : name => v if v.kms_key_arn != "" && !startswith(v.kms_key_arn, "arn:") }

  plans = {
    for name, f in local.plan_files : name => {
      tags = try(tomap(f.tags), {})
      rule = [
        for r in try([for x in f.rule : x], []) : {
          rule_name                    = try(tostring(r.rule_name), "")
          target_vault_name            = try(tostring(r.target_vault_name), "")
          schedule                     = try(tostring(r.schedule), null)
          schedule_expression_timezone = try(tostring(r.schedule_expression_timezone), null)
          start_window                 = try(tonumber(r.start_window), null)
          completion_window            = try(tonumber(r.completion_window), null)
          enable_continuous_backup     = try(tobool(r.enable_continuous_backup), null)
          recovery_point_tags          = try(tomap(r.recovery_point_tags), null)
          lifecycle                    = can(r.lifecycle) ? { delete_after = try(tonumber(r.lifecycle.delete_after), null), cold_storage_after = try(tonumber(r.lifecycle.cold_storage_after), null) } : null
          copy_action = [
            for c in try([for x in r.copy_action : x], []) : {
              destination_vault_arn = try(tostring(c.destination_vault_arn), "")
              lifecycle             = can(c.lifecycle) ? { delete_after = try(tonumber(c.lifecycle.delete_after), null), cold_storage_after = try(tonumber(c.lifecycle.cold_storage_after), null) } : null
            }
          ]
        }
      ]
    }
  }
  rules = flatten([for name, p in local.plans : [for r in p.rule : merge(r, { plan = name })]])
  kept = flatten([for r in local.rules : concat(
    [{ plan = r.plan, rule = r.rule_name, vault = r.target_vault_name, days = try(r.lifecycle.delete_after, null) }],
    [for c in r.copy_action : { plan = r.plan, rule = r.rule_name, vault = c.destination_vault_arn, days = try(c.lifecycle.delete_after, null) } if contains(keys(local.vaults), c.destination_vault_arn)],
  )])

  problems = concat(
    [for p in local.paths : "${p}: files go in backup-vault/ or backup-plan/" if local.in_kind[p] == null],
    flatten([for folder, names in local.found : [for name, paths in names : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a file's name is what it builds, so it must be unique" if length(paths) > 1]]),
    [for name, f in local.vault_files : "backup-vault/${name}.yml: keys are ${join(", ", local.vault_keys)}, as aws_backup_vault takes them, and lock_configuration for its aws_backup_vault_lock_configuration" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.vault_keys, k)])],
    [for name, v in local.vaults : "backup-vault/${name}.yml: needs kms_key_arn: the backup key by alias name (${var.environment}-backup), or its ARN" if v.kms_key_arn == ""],
    [for name, f in local.vault_files : "backup-vault/${name}.yml: needs lock_configuration, with min_retention_days and any of ${join(", ", local.lock_keys)}: every vault is locked" if !can(tonumber(f.lock_configuration.min_retention_days)) || !alltrue([for k in try(keys(f.lock_configuration), []) : contains(local.lock_keys, k)])],
    [for name, v in local.vaults : "backup-vault/${name}.yml: region ${v.region} is not a region in config/ (${join(", ", local.regions)})" if v.region != null && !contains(local.regions, coalesce(v.region, "-"))],
    [for name, f in local.plan_files : "backup-plan/${name}.yml: keys are ${join(", ", local.plan_keys)}, as aws_backup_plan takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.plan_keys, k)]) || !(can([for x in f.rule : x]) && !can(keys(f.rule)))],
    flatten([for name, f in local.plan_files : [
      for r in try([for x in f.rule : x], []) : "backup-plan/${name}.yml: a rule takes ${join(", ", local.rule_keys)}, and needs rule_name and target_vault_name; lifecycle takes ${join(", ", local.lifecycle_keys)}, copy_action is a list of destination_vault_arn and lifecycle"
      if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)]) || !can(tostring(r.rule_name)) || !can(tostring(r.target_vault_name))
      || !alltrue([for k in try(keys(r.lifecycle), []) : contains(local.lifecycle_keys, k)])
      || !alltrue([for c in try([for x in r.copy_action : x], []) : alltrue([for k in try(keys(c), ["?"]) : contains(["destination_vault_arn", "lifecycle"], k)]) && can(tostring(c.destination_vault_arn))])
    ]]),
    [for r in local.rules : "backup-plan/${r.plan}.yml: rule ${r.rule_name}: target_vault_name ${r.target_vault_name} is not a vault in this stack (a file in backup-vault/)" if !contains(keys(local.vaults), r.target_vault_name)],
    [for r in local.rules : "backup-plan/${r.plan}.yml: rule ${r.rule_name}: target_vault_name ${r.target_vault_name} is in ${local.vaults[r.target_vault_name].region}; a plan backs up into a vault in its own region, ${var.region}" if contains(keys(local.vaults), r.target_vault_name) && coalesce(try(local.vaults[r.target_vault_name].region, null), var.region) != var.region],
    flatten([for r in local.rules : [for c in r.copy_action : "backup-plan/${r.plan}.yml: rule ${r.rule_name}: destination_vault_arn ${c.destination_vault_arn} is not a vault in this stack (a file in backup-vault/) or a vault's ARN" if !contains(keys(local.vaults), c.destination_vault_arn) && !startswith(c.destination_vault_arn, "arn:")]]),
    [for k in local.kept : "backup-plan/${k.plan}.yml: rule ${k.rule} keeps backups in ${k.vault} ${k.days == null ? "forever" : "${k.days} days"}, outside its lock (${local.vaults[k.vault].lock_configuration.min_retention_days} to ${coalesce(local.vaults[k.vault].lock_configuration.max_retention_days, "any")} days), so every backup would fail; set lifecycle.delete_after within it" if contains(keys(local.vaults), k.vault) && (try(k.days < local.vaults[k.vault].lock_configuration.min_retention_days, false) || (local.vaults[k.vault].lock_configuration.max_retention_days != null && try(k.days > local.vaults[k.vault].lock_configuration.max_retention_days, true)))],
  )

  ready = length(local.problems) == 0
}
