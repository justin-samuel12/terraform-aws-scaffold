locals {
  postgres = var.engine == "aurora-postgresql"
  family   = local.postgres ? "aurora-postgresql${split(".", var.engine_version)[0]}" : "aurora-mysql${join(".", slice(split(".", var.engine_version), 0, 2))}"
  port     = local.postgres ? 5432 : 3306

  # Every connection must use TLS; slow statements are logged.
  parameters = local.postgres ? { "rds.force_ssl" = "1", log_min_duration_statement = "1000" } : { require_secure_transport = "ON", slow_query_log = "1", long_query_time = "1" }

  log_exports = local.postgres ? ["postgresql"] : ["error", "slowquery"]
}
