locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "
  short_name      = trimprefix(var.name, "${local.environment_tag}-")

  postgres = var.engine == "aurora-postgresql"
  pinned   = local.postgres ? length(split(".", var.engine_version)) > 1 : strcontains(var.engine_version, "mysql_aurora")
  family   = local.postgres ? "aurora-postgresql${split(".", var.engine_version)[0]}" : "aurora-mysql${join(".", slice(split(".", var.engine_version), 0, 2))}"
  port     = local.postgres ? 5432 : 3306

  parameters = local.postgres ? { "rds.force_ssl" = "1", log_min_duration_statement = "1000" } : { require_secure_transport = "ON", slow_query_log = "1", long_query_time = "1" }

  log_exports = local.postgres ? ["postgresql"] : ["error", "slowquery"]
}
