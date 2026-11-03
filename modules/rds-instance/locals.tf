locals {
  sqlserver = startswith(var.engine, "sqlserver-")
  custom    = startswith(var.engine, "custom-")
  major     = split(".", var.engine_version)[0]

  # SQL Server's families and option groups are named by edition and major version: sqlserver-se-16.0, 16.00.
  family = local.sqlserver ? "${var.engine}-${local.major}.0" : "${var.engine}${var.engine_version}"

  # Every connection must use TLS; slow statements are logged. SSIS runs on the CLR.
  parameters = local.custom ? {} : local.sqlserver ? merge({ "rds.force_ssl" = "1" }, contains(keys(var.options), "SSIS") ? { "clr enabled" = "1" } : {}) : {
    mysql    = { require_secure_transport = "1", slow_query_log = "1", long_query_time = "1" }
    mariadb  = { require_secure_transport = "1", slow_query_log = "1", long_query_time = "1" }
    postgres = { "rds.force_ssl" = "1", log_min_duration_statement = "1000" }
  }[var.engine]

  # RDS Custom exports nothing; its logs stay on the server.
  log_exports = local.custom ? [] : local.sqlserver ? ["agent", "error"] : {
    mysql    = ["error", "slowquery"]
    mariadb  = ["error", "slowquery"]
    postgres = ["postgresql", "upgrade"]
  }[var.engine]

  # Two random UUIDs: upper and lower case, digits and hyphens, as SQL Server's password rules want. Only write-only arguments read it.
  password = "${upper(uuid())}-${uuid()}"

  # Options that listen on a port are reached through the database's own security groups.
  options = merge(
    { for name, o in var.options : name => { port = o.port, settings = o.settings, security_groups = o.port == null ? [] : var.security_group_ids } },
    var.backup_restore_bucket == null ? {} : { SQLSERVER_BACKUP_RESTORE = { port = null, settings = { IAM_ROLE_ARN = aws_iam_role.backup_restore[0].arn }, security_groups = [] } },
  )
}
