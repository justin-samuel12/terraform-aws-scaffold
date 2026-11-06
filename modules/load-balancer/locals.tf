locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "
  short_name      = trimprefix(var.name, "${local.environment_tag}-")

  listeners = { for l in var.listeners : tostring(l.port) => l }

  target_group_names = {
    for target, t in var.target_groups : target => (
      length("${var.name}-${target}") <= 23
      ? "${var.name}-${target}-${substr(sha1("${var.name}/${target}/${t.port}/${t.protocol}"), 0, 8)}"
      : "${substr("${var.name}-${target}", 0, 23)}-${substr(sha1("${var.name}/${target}/${t.port}/${t.protocol}"), 0, 8)}"
    )
  }
}
