locals {
  family = "${var.engine}${var.engine_version}"

  # Every connection must use TLS; slow statements are logged.
  parameters = {
    mysql    = { require_secure_transport = "1", slow_query_log = "1", long_query_time = "1" }
    mariadb  = { require_secure_transport = "1", slow_query_log = "1", long_query_time = "1" }
    postgres = { "rds.force_ssl" = "1", log_min_duration_statement = "1000" }
  }[var.engine]

  log_exports = {
    mysql    = ["error", "slowquery"]
    mariadb  = ["error", "slowquery"]
    postgres = ["postgresql", "upgrade"]
  }[var.engine]
}
