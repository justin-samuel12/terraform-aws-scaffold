locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }

  # SQL Server versions of our own, for RDS Custom: engine-versions/<name>.yml, each named by its engine_version in a database file.
  version_files = { for name in fileset(local.config_dir, "engine-versions/*.yml") : trimsuffix(basename(name), ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  version_keys  = ["engine", "engine_version", "source_image_id", "description"]
  custom_versions = {
    for name, f in local.version_files : tostring(f.engine_version) => { file = name, engine = try(tostring(f.engine), "") }
    if can(tostring(f.engine_version)) && length([for g in values(local.version_files) : g if try(tostring(g.engine_version), "") == tostring(f.engine_version)]) == 1
  }

  # The engine decides the kind of database, and the kind which keys a file may use.
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
  rds_keys = ["engine", "engine_version", "instance_class", "allocated_storage", "max_allocated_storage", "multi_az", "security_groups"]
  keys = {
    rds        = local.rds_keys
    sqlserver  = concat(local.rds_keys, ["timezone", "character_set_name", "options", "domain"], local.domain)
    rds-custom = concat(["engine", "engine_version", "instance_class", "allocated_storage", "multi_az", "security_groups", "license_model", "timezone", "character_set_name", "password_generation"], local.domain)
    aurora     = ["engine", "engine_version", "instance_class", "instances", "serverlessv2_scaling_configuration", "security_groups"]
  }
  required = {
    rds        = ["engine", "engine_version", "instance_class", "allocated_storage"]
    sqlserver  = ["engine", "engine_version", "instance_class", "allocated_storage"]
    rds-custom = ["engine", "engine_version", "instance_class", "allocated_storage"]
    aurora     = ["engine", "engine_version", "instance_class"]
  }

  # SQL Server's options: the editions and major versions each runs on, and the port it listens on.
  sqlserver_options = {
    SQLSERVER_BACKUP_RESTORE = { editions = ["ex", "web", "se", "ee"], majors = [13, 14, 15, 16, 17], port = null }
    TDE                      = { editions = ["se", "ee"], majors = [13, 14, 15, 16, 17], port = null }
    SSIS                     = { editions = ["se", "ee"], majors = [13, 14, 15, 16], port = null }
    SSRS                     = { editions = ["se", "ee"], majors = [13, 14, 15, 16], port = 8443 }
    PBIRS                    = { editions = ["se", "ee"], majors = [17], port = 8443 }
    SSAS                     = { editions = ["se", "ee"], majors = [13, 14, 15], port = 2383 }
  }
  windows_options = ["SSIS", "SSRS", "PBIRS", "SSAS"]

  kinds = { for name, f in local.files : name => lookup(local.kind_of, try(tostring(f.engine), ""), null) }
  facts = {
    for name, f in local.files : name => {
      engine   = try(tostring(f.engine), "")
      edition  = reverse(split("-", try(tostring(f.engine), "")))[0]
      version  = try(tostring(f.engine_version), "")
      major    = try(tonumber(split(".", tostring(f.engine_version))[0]), 0)
      build    = try(tonumber(split(".", tostring(f.engine_version))[2]), null)
      multi_az = try(tobool(f.multi_az), contains(["sqlserver-se", "sqlserver-ee"], try(tostring(f.engine), "")) || contains(local.engines.rds, try(tostring(f.engine), "")) || startswith(try(tostring(f.engine), ""), "custom-"))
      options  = try({ for k, v in f.options : k => v }, {})
      license  = try(tostring(f.license_model), try(tostring(f.engine), "") == "custom-sqlserver-dev" ? "bring-your-own-media" : "license-included")
      joins_ad = can(f.domain) || can(f.domain_fqdn)
    }
  }

  file_problems = {
    for name, f in local.files : name => local.kinds[name] == null ? [
      "${name}.yml: engine must be one of ${join(", ", flatten([for kind in local.order : local.engines[kind]]))}"
      ] : concat(
      [
        for k in try(keys(f), []) : (
          length([for kind in local.order : kind if contains(local.keys[kind], k)]) > 0
          ? "${name}.yml: ${k} is for ${join(", ", [for kind in local.order : local.labels[kind] if contains(local.keys[kind], k)])}, not ${local.labels[local.kinds[name]]} (engine ${f.engine}); its keys are ${join(", ", local.keys[local.kinds[name]])}"
          : "${name}.yml: ${k} is not a database key; ${local.labels[local.kinds[name]]} takes ${join(", ", local.keys[local.kinds[name]])}"
        ) if !contains(local.keys[local.kinds[name]], k)
      ],
      [for k in local.required[local.kinds[name]] : "${name}.yml: needs ${k}" if !can(f[k])],
      [for k in ["allocated_storage", "max_allocated_storage", "instances"] : "${name}.yml: ${k} is a whole number" if can(f[k]) && !try(tonumber(f[k]) == floor(tonumber(f[k])), false)],

      # RDS for SQL Server.
      local.kinds[name] != "sqlserver" ? [] : concat(
        can(regex("^[0-9]+\\.00(\\.[0-9]+\\.[0-9]+\\.v[0-9]+)?$", local.facts[name].version)) && contains([13, 14, 15, 16, 17], local.facts[name].major) ? [] : ["${name}.yml: engine_version is SQL Server's major version, 13.00 (2016) to 17.00 (2025), or a full version such as 16.00.4185.3.v1"],
        try(tonumber(f.allocated_storage) >= 20, true) ? [] : ["${name}.yml: SQL Server needs allocated_storage of at least 20 GB"],
        local.facts[name].engine == "sqlserver-ex" && local.facts[name].multi_az ? ["${name}.yml: SQL Server Express cannot be Multi-AZ; set multi_az: false, or choose Standard (sqlserver-se) or Enterprise (sqlserver-ee)"] : [],
        local.facts[name].engine == "sqlserver-web" && local.facts[name].multi_az && !(local.facts[name].major == 16 && try(local.facts[name].build >= 4215, true)) ? ["${name}.yml: SQL Server Web edition is Multi-AZ only from SQL Server 2022 (16.00.4215.2 on); set multi_az: false or engine_version: \"16.00\""] : [],
        can(f.options) && !can(keys(f.options)) ? ["${name}.yml: options is a map of option name to its settings, such as TDE: {}"] : [],
        [for o in keys(local.facts[name].options) : "${name}.yml: options are ${join(", ", keys(local.sqlserver_options))}, not ${o}" if !contains(keys(local.sqlserver_options), o)],
        [for o in keys(local.facts[name].options) : "${name}.yml: ${o} needs Standard (sqlserver-se) or Enterprise (sqlserver-ee) edition" if contains(keys(local.sqlserver_options), o) && !contains(try(local.sqlserver_options[o].editions, []), local.facts[name].edition)],
        [for o in keys(local.facts[name].options) : "${name}.yml: ${o} does not run on SQL Server ${local.facts[name].major}.00; it runs on ${join(", ", [for m in local.sqlserver_options[o].majors : "${m}.00"])}" if contains(keys(local.sqlserver_options), o) && !contains(try(local.sqlserver_options[o].majors, []), local.facts[name].major)],
        contains(keys(local.facts[name].options), "TDE") && local.facts[name].edition == "se" && local.facts[name].major < 15 ? ["${name}.yml: TDE on Standard edition needs SQL Server 2019 (15.00) or later"] : [],
        contains(keys(local.facts[name].options), "SSAS") && local.facts[name].multi_az ? ["${name}.yml: SSAS does not run on a Multi-AZ database; set multi_az: false"] : [],
        [for o in keys(local.facts[name].options) : "${name}.yml: ${o} signs people in through Windows, so the database must join Active Directory (domain, or domain_fqdn and its companions)" if contains(local.windows_options, o) && !local.facts[name].joins_ad],
        contains(keys(local.facts[name].options), "SQLSERVER_BACKUP_RESTORE") && !can(tostring(try(local.facts[name].options.SQLSERVER_BACKUP_RESTORE.bucket, null))) ? ["${name}.yml: SQLSERVER_BACKUP_RESTORE needs bucket, a bucket from the buckets stack by its file name"] : [],
        [for o, v in local.facts[name].options : "${name}.yml: ${o} takes its option settings by AWS name${local.sqlserver_options[o].port == null ? "" : ", and port"}" if contains(keys(local.sqlserver_options), o) && o != "SQLSERVER_BACKUP_RESTORE" && v != null && !can({ for k, s in v : k => tostring(s) })],
        can(f.domain) && can(f.domain_fqdn) ? ["${name}.yml: join AWS Managed Microsoft AD (domain) or a self-managed domain (domain_fqdn), not both"] : [],
      ),

      # RDS Custom for SQL Server.
      local.kinds[name] != "rds-custom" ? [] : concat(
        can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\.[A-Za-z0-9_-]+$", local.facts[name].version)) ? [] : ["${name}.yml: RDS Custom takes a full engine_version: AWS's, such as 16.00.4185.3.v1, or one of ours from engine-versions/"],
        contains(["license-included", "bring-your-own-media"], local.facts[name].license) ? [] : ["${name}.yml: license_model is license-included or bring-your-own-media"],
        local.facts[name].engine == "custom-sqlserver-dev" && local.facts[name].license != "bring-your-own-media" ? ["${name}.yml: Developer edition comes only from our own media: license_model bring-your-own-media"] : [],
        local.facts[name].engine == "custom-sqlserver-web" && local.facts[name].license == "bring-your-own-media" ? ["${name}.yml: Web edition cannot bring its own media; it is license-included"] : [],
        local.facts[name].license == "bring-your-own-media" && can(regex("\\.v[0-9]+$", local.facts[name].version)) ? ["${name}.yml: bring-your-own-media runs a version of our own, from engine-versions/, not AWS's ${local.facts[name].version}"] : [],
        !can(regex("\\.v[0-9]+$", local.facts[name].version)) && local.facts[name].version != "" && !contains(keys(local.custom_versions), local.facts[name].version) ? ["${name}.yml: engine_version ${local.facts[name].version} is a version of our own, but no file in engine-versions/ defines it"] : [],
        try(local.custom_versions[local.facts[name].version].engine, local.facts[name].engine) != local.facts[name].engine ? ["${name}.yml: engine-versions/${try(local.custom_versions[local.facts[name].version].file, "")}.yml is for ${try(local.custom_versions[local.facts[name].version].engine, "")}, not ${local.facts[name].engine}"] : [],
        try(tonumber(f.allocated_storage) >= 20, true) ? [] : ["${name}.yml: RDS Custom needs allocated_storage of at least 20 GB"],
      ),

      # Active Directory, for both kinds of SQL Server.
      contains(["sqlserver", "rds-custom"], local.kinds[name]) && length([for k in local.domain : k if can(f[k])]) > 0 && length([for k in local.domain : k if can(f[k])]) < 4 ? ["${name}.yml: a self-managed domain needs all of ${join(", ", local.domain)}"] : [],
      can(f.domain_dns_ips) && length(try(tolist(f.domain_dns_ips), [])) != 2 ? ["${name}.yml: domain_dns_ips is two domain controllers' addresses (the same one twice if there is only one)"] : [],

      # Aurora.
      local.kinds[name] != "aurora" ? [] : concat(
        can(regex("^[0-9]+(\\.[0-9]+)?(\\.mysql_aurora\\.[0-9.]+)?$", local.facts[name].version)) ? [] : ["${name}.yml: engine_version is a version such as 16.6 or 8.0.mysql_aurora.3.08.0"],
        try(tonumber(f.instances) >= 1 && tonumber(f.instances) <= 15, !can(f.instances)) ? [] : ["${name}.yml: instances is 1 to 15: the writer, then readers that take over by themselves"],
        try(tostring(f.instance_class), "") == "db.serverless" && !can(f.serverlessv2_scaling_configuration) ? ["${name}.yml: Serverless v2 (db.serverless) needs serverlessv2_scaling_configuration: min_capacity and max_capacity"] : [],
        try(tostring(f.instance_class), "") != "db.serverless" && can(f.serverlessv2_scaling_configuration) ? ["${name}.yml: serverlessv2_scaling_configuration is for instance_class db.serverless only"] : [],
        !can(f.serverlessv2_scaling_configuration) || try(alltrue([for k in keys(f.serverlessv2_scaling_configuration) : contains(["min_capacity", "max_capacity"], k)]) && tonumber(f.serverlessv2_scaling_configuration.min_capacity) >= 0 && tonumber(f.serverlessv2_scaling_configuration.min_capacity) <= tonumber(f.serverlessv2_scaling_configuration.max_capacity) && tonumber(f.serverlessv2_scaling_configuration.max_capacity) <= 256, false) ? [] : ["${name}.yml: serverlessv2_scaling_configuration takes min_capacity and max_capacity, 0 to 256 ACUs, min no more than max"],
      ),
    )
  }

  version_problems = concat(
    flatten([for name, f in local.version_files : [
      [for k in try(keys(f), []) : "engine-versions/${name}.yml: ${k} is not a key; they are ${join(", ", local.version_keys)}" if !contains(local.version_keys, k)],
      [for k in local.version_keys : "engine-versions/${name}.yml: needs ${k}" if !can(f[k])],
      contains(local.engines.rds-custom, try(tostring(f.engine), "")) ? [] : ["engine-versions/${name}.yml: engine is one of ${join(", ", local.engines.rds-custom)}"],
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+\\.[A-Za-z0-9_-]+$", try(tostring(f.engine_version), ""))) && !can(regex("\\.v[0-9]+$", try(tostring(f.engine_version), ""))) ? [] : ["engine-versions/${name}.yml: engine_version is SQL Server's version on the image and a name of our own, such as 16.00.4185.3.dbamp-v1 (not ending .v<number>, which is AWS's)"],
      can(f.engine_version) && !contains(keys(local.custom_versions), try(tostring(f.engine_version), "")) ? ["engine-versions/${name}.yml: another file defines engine_version ${try(tostring(f.engine_version), "")} too"] : [],
    ]]),
  )

  problems  = concat(flatten(values(local.file_problems)), local.version_problems)
  databases = { for name, f in local.files : name => merge(f, { kind = local.kinds[name] }, local.facts[name]) if length(local.file_problems[name]) == 0 }
  instances = { for name, d in local.databases : name => d if d.kind != "aurora" }
  clusters  = { for name, d in local.databases : name => d if d.kind == "aurora" }
  versions  = { for name, f in local.version_files : name => f if length([for p in local.version_problems : p if startswith(p, "engine-versions/${name}.yml:")]) == 0 }

  monitored       = length([for d in local.databases : d if d.kind != "rds-custom"]) > 0
  managed_ad      = length([for d in local.databases : d if can(d.domain)]) > 0
  any_custom      = length([for d in local.databases : d if d.kind == "rds-custom"]) > 0
  instance_prefix = "AWSRDSCustom-${var.environment}-${data.aws_region.current.region}"
}
