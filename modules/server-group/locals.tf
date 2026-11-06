locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  routed = length(var.routes) > 0

  target_group_names = concat(aws_lb_target_group.group[*].name, [for t in values(var.targets) : t.name])

  target_group_suffix = substr(sha1("${var.environment}/${var.name}/${coalesce(var.port, 0)}/${var.target.protocol}"), 0, 8)
}
