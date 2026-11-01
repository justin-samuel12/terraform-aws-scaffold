module "lambda_function" {
  source   = "../../modules/lambda-function"
  for_each = { for name, f in local.files : name => f if length(fileset("${local.config_dir}/src/${name}", "**")) > 0 }

  name               = each.key
  source_dir         = "${local.config_dir}/src/${each.key}"
  runtime            = each.value.runtime
  handler            = each.value.handler
  memory             = try(each.value.memory, 256)
  timeout            = try(each.value.timeout, 30)
  environment        = { for k, v in try(each.value.environment, {}) : k => tostring(v) }
  statements         = [for s in try(each.value.statements, []) : { actions = tolist(s.actions), resources = tolist(s.resources) }]
  schedule           = try(each.value.schedule, null)
  log_retention_days = try(each.value.log_retention_days, 365)
}
