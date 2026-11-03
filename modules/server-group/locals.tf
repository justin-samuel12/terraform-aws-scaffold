locals {
  routed = length(var.routes) > 0

  target_group_names = concat(aws_lb_target_group.group[*].name, [for t in values(var.targets) : t.name])

  # AWS allows 32 characters for a target group's name; the suffix comes from what AWS cannot change in place.
  target_group_suffix = substr(sha1("${var.environment}/${var.name}/${coalesce(var.port, 0)}/${var.target.protocol}"), 0, 8)
}
