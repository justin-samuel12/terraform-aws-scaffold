locals {
  config_dir     = coalesce(var.config_dir, "${path.root}/config")
  paths          = [for p in fileset(local.config_dir, "**/*.yml") : p]
  is_version     = { for p in local.paths : p => can(regex("(^|/)engine-versions/", p)) }
  found          = { for p in local.paths : trimsuffix(basename(p), ".yml") => p... if !local.is_version[p] }
  raw_files      = { for name, paths in local.found : name => try(merge({}, yamldecode(file("${local.config_dir}/${sort(paths)[0]}"))), "not a map") }
  blueprints_dir = abspath(coalesce(var.blueprints_dir, "${path.root}/../../../../blueprints/databases"))
  files          = module.blueprint.files

  version_files = { for p in local.paths : trimsuffix(basename(p), ".yml") => yamldecode(file("${local.config_dir}/${p}")) if local.is_version[p] }
  version_keys  = ["engine", "engine_version", "source_image_id", "description"]
  custom_versions = {
    for name, f in local.version_files : tostring(f.engine_version) => { file = name, engine = try(tostring(f.engine), "") }
    if can(tostring(f.engine_version)) && length([for g in values(local.version_files) : g if try(tostring(g.engine_version), "") == tostring(f.engine_version)]) == 1
  }

  engines = {
    rds        = ["mysql", "postgres", "mariadb"]
    sqlserver  = ["sqlserver-ex", "sqlserver-web", "sqlserver-se", "sqlserver-ee"]
    rds-custom = ["custom-sqlserver-ee", "custom-sqlserver-se", "custom-sqlserver-web", "custom-sqlserver-dev"]
    aurora     = ["aurora-postgresql", "aurora-mysql"]
  }
  order    = ["rds", "sqlserver", "rds-custom", "aurora"]
  labels   = { rds = "RDS", sqlserver = "RDS for SQL Server", rds-custom = "RDS Custom for SQL Server", aurora = "Aurora" }
  kind_of  = merge([for kind in local.order : { for e in local.engines[kind] : e => kind }]...)
  domain   = ["domain_fqdn", "domain_ou", "domain_auth_secret_arn", "domain_dns_ips"]
  rds_keys = ["engine", "engine_version", "instance_class", "allocated_storage", "max_allocated_storage", "multi_az", "vpc_security_group_ids", "tags"]
  keys = {
    rds        = local.rds_keys
    sqlserver  = concat(local.rds_keys, ["license_model", "timezone", "character_set_name", "option", "domain", "domain_iam_role_name"], local.domain)
    rds-custom = concat(["engine", "engine_version", "instance_class", "allocated_storage", "multi_az", "vpc_security_group_ids", "license_model", "timezone", "character_set_name", "password_wo_version", "tags"], local.domain)
    aurora     = ["engine", "engine_version", "instance_class", "count", "serverlessv2_scaling_configuration", "vpc_security_group_ids", "tags"]
  }
  required = {
    rds        = ["engine", "engine_version", "instance_class", "allocated_storage"]
    sqlserver  = ["engine", "engine_version", "instance_class", "allocated_storage"]
    rds-custom = ["engine", "engine_version", "instance_class", "allocated_storage", "password_wo_version"]
    aurora     = ["engine", "engine_version", "instance_class", "count"]
  }
  option_keys  = ["option_name", "port", "version", "vpc_security_group_memberships", "option_settings"]
  version_form = { rds = "^[0-9]+(\\.[0-9]+)?$", sqlserver = "^[0-9]+\\.00(\\.[0-9]+\\.[0-9]+\\.v[0-9]+)?$", rds-custom = "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\.[A-Za-z0-9_-]+$", aurora = "^[0-9]+(\\.[0-9]+)?(\\.mysql_aurora\\.[0-9.]+)?$" }
  version_hint = { rds = "a major version such as 8.0 or 16", sqlserver = "SQL Server's major version, such as 16.00, or a full version such as 16.00.4185.3.v1", rds-custom = "a full version: AWS's, such as 16.00.4185.3.v1, or one of ours from engine-versions/", aurora = "a version such as 16.6 or 8.0.mysql_aurora.3.08.0" }

  kinds    = { for name, f in local.files : name => lookup(local.kind_of, try(tostring(f.engine), ""), null) }
  versions = { for name, f in local.files : name => try(tostring(f.engine_version), "") }
  options  = { for name, f in local.files : name => [for o in try([for x in f.option : x], []) : o] }

  file_problems = {
    for name, f in local.files : name => local.kinds[name] == null ? [
      "${name}.yml: engine must be one of ${join(", ", flatten([for kind in local.order : local.engines[kind]]))}"
      ] : concat(
      [
        for k in try(keys(f), []) : (
          length([for kind in local.order : kind if contains(local.keys[kind], k)]) > 0
          ? "${name}.yml: ${k} is for ${join(", ", [for kind in local.order : local.labels[kind] if contains(local.keys[kind], k)])}, not ${local.labels[local.kinds[name]]} (engine ${f.engine}); its keys are ${join(", ", local.keys[local.kinds[name]])}"
          : "${name}.yml: ${k} is not an argument here; ${local.labels[local.kinds[name]]} takes ${join(", ", local.keys[local.kinds[name]])}"
        ) if !contains(local.keys[local.kinds[name]], k)
      ],
      [for k in local.required[local.kinds[name]] : "${name}.yml: needs ${k}" if !can(f[k])],
      [for k in ["allocated_storage", "max_allocated_storage", "count", "password_wo_version"] : "${name}.yml: ${k} is a whole number" if can(f[k]) && !try(tonumber(f[k]) == floor(tonumber(f[k])), false)],
      can(regex(local.version_form[local.kinds[name]], local.versions[name])) ? [] : ["${name}.yml: engine_version is ${local.version_hint[local.kinds[name]]}"],
      can(f.vpc_security_group_ids) && !can([for g in f.vpc_security_group_ids : tostring(g)]) ? ["${name}.yml: vpc_security_group_ids is a list of groups, by name or sg- ID"] : [],
      can(f.option) && !(can([for x in f.option : x]) && !can(keys(f.option))) ? ["${name}.yml: option is a list, each with option_name"] : [],
      [
        for o in local.options[name] : "${name}.yml: an option takes ${join(", ", local.option_keys)}, and needs option_name; option_settings is a list of name and value"
        if !can(tostring(o.option_name)) || !alltrue([for k in try(keys(o), []) : contains(local.option_keys, k)]) || !alltrue([for s in try([for x in o.option_settings : x], []) : try(toset(keys(s)) == toset(["name", "value"]), false)])
      ],
      can(f.domain) != can(f.domain_iam_role_name) ? ["${name}.yml: domain and domain_iam_role_name go together: the directory, and the role RDS joins it with (from the iam stack)"] : [],
      local.kinds[name] != "rds-custom" || can(regex("\\.v[0-9]+$", local.versions[name])) || local.versions[name] == "" || contains(keys(local.custom_versions), local.versions[name]) ? [] : ["${name}.yml: engine_version ${local.versions[name]} is a version of our own, but no file in engine-versions/ defines it"],
      local.kinds[name] == "rds-custom" && try(local.custom_versions[local.versions[name]].engine, f.engine) != f.engine ? ["${name}.yml: engine-versions/${try(local.custom_versions[local.versions[name]].file, "")}.yml is for ${try(local.custom_versions[local.versions[name]].engine, "")}, not ${f.engine}"] : [],
      local.kinds[name] == "aurora" && (try(tostring(f.instance_class), "") == "db.serverless") != can(f.serverlessv2_scaling_configuration) ? ["${name}.yml: Serverless v2 (instance_class db.serverless) needs serverlessv2_scaling_configuration, with min_capacity and max_capacity, and only it takes one"] : [],
      can(f.serverlessv2_scaling_configuration) && !try(toset(keys(f.serverlessv2_scaling_configuration)) == toset(["min_capacity", "max_capacity"]), false) ? ["${name}.yml: serverlessv2_scaling_configuration takes min_capacity and max_capacity"] : [],
    )
  }

  version_problems = concat(
    flatten([for name, f in local.version_files : [
      [for k in try(keys(f), []) : "engine-versions/${name}.yml: ${k} is not an argument; aws_rds_custom_db_engine_version takes ${join(", ", local.version_keys)} here" if !contains(local.version_keys, k)],
      [for k in local.version_keys : "engine-versions/${name}.yml: needs ${k}" if !can(f[k])],
      contains(local.engines.rds-custom, try(tostring(f.engine), "")) ? [] : ["engine-versions/${name}.yml: engine is one of ${join(", ", local.engines.rds-custom)}"],
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\.[A-Za-z0-9_-]+$", try(tostring(f.engine_version), ""))) && !can(regex("\\.v[0-9]+$", try(tostring(f.engine_version), ""))) ? [] : ["engine-versions/${name}.yml: engine_version is SQL Server's version on the image and a name of our own, such as 16.00.4185.3.dbamp-v1 (not ending .v<number>, which is AWS's)"],
      can(f.engine_version) && !contains(keys(local.custom_versions), try(tostring(f.engine_version), "")) ? ["engine-versions/${name}.yml: another file defines engine_version ${try(tostring(f.engine_version), "")} too"] : [],
    ]]),
  )

  problems = concat(
    module.blueprint.problems,
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a database's name is its file's, so it must be unique" if length(paths) > 1],
    flatten([for name, f in local.files : [for k in keys(try(f.tags, {})) : "${name}.yml: the tag ${k} is the stack's own; give yours another name" if contains(["Name", "Backup"], k)]]),
    flatten(values(local.file_problems)),
    local.version_problems,
  )
  databases   = { for name, f in local.files : name => merge(f, { kind = local.kinds[name] }) if length(local.file_problems[name]) == 0 }
  instances   = { for name, d in local.databases : name => d if d.kind != "aurora" }
  clusters    = { for name, d in local.databases : name => d if d.kind == "aurora" }
  versions_ok = { for name, f in local.version_files : name => f if length([for p in local.version_problems : p if startswith(p, "engine-versions/${name}.yml:")]) == 0 }

  group_names = toset(flatten([for d in local.databases : [for g in concat(try([for x in d.vpc_security_group_ids : tostring(x)], []), flatten([for o in try([for x in d.option : x], []) : try([for x in o.vpc_security_group_memberships : tostring(x)], [])])) : g if !startswith(g, "sg-")]]))
  group_id    = { for g in local.group_names : g => data.aws_security_group.groups[g].id }
  role_names = toset(flatten([for d in local.databases : [
    for o in try([for x in d.option : x], []) : [for s in try([for x in o.option_settings : x], []) : tostring(s.value) if tostring(s.name) == "IAM_ROLE_ARN" && !startswith(tostring(s.value), "arn:")]
  ]]))

  option_args = {
    for name, d in local.instances : name => [
      for o in try([for x in d.option : x], []) : {
        option_name                    = tostring(o.option_name)
        port                           = try(tonumber(o.port), null)
        version                        = try(tostring(o.version), null)
        vpc_security_group_memberships = can(o.vpc_security_group_memberships) ? [for g in o.vpc_security_group_memberships : lookup(local.group_id, tostring(g), tostring(g))] : null
        option_settings = [
          for s in try([for x in o.option_settings : x], []) : {
            name  = tostring(s.name)
            value = tostring(s.name) == "IAM_ROLE_ARN" && contains(local.role_names, tostring(s.value)) ? data.aws_iam_role.options[tostring(s.value)].arn : tostring(s.value)
          }
        ]
      }
    ]
  }

  monitored       = length([for d in local.databases : d if d.kind != "rds-custom"]) > 0
  any_custom      = length([for d in local.databases : d if d.kind == "rds-custom"]) > 0
  instance_prefix = "AWSRDSCustom-${var.environment}-${data.aws_region.current.region}"
}
