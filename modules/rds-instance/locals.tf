locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "
  short_name      = trimprefix(var.name, "${local.environment_tag}-")

  sqlserver = startswith(var.engine, "sqlserver-")
  custom    = startswith(var.engine, "custom-")
  major     = split(".", var.engine_version)[0]
  pinned    = length(split(".", var.engine_version)) > (var.engine == "postgres" ? 1 : 2)

  family = local.sqlserver ? "${var.engine}-${local.major}.0" : "${var.engine}${var.engine_version}"

  parameters = local.custom ? {} : local.sqlserver ? merge({ "rds.force_ssl" = "1" }, contains([for o in var.option : o.option_name], "SSIS") ? { "clr enabled" = "1" } : {}) : {
    mysql    = { require_secure_transport = "1", slow_query_log = "1", long_query_time = "1" }
    mariadb  = { require_secure_transport = "1", slow_query_log = "1", long_query_time = "1" }
    postgres = { "rds.force_ssl" = "1", log_min_duration_statement = "1000" }
  }[var.engine]

  log_exports = local.custom ? [] : local.sqlserver ? ["agent", "error"] : {
    mysql    = ["error", "slowquery"]
    mariadb  = ["error", "slowquery"]
    postgres = ["postgresql", "upgrade"]
  }[var.engine]

  password = "${upper(uuid())}-${uuid()}"

}
