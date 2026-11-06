locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  own  = merge({ Group = var.group, PatchGroup = var.environment }, var.backup ? { Backup = "standard" } : {})
  tags = merge(var.tags, local.own)

  volumes = merge([for member in keys(var.members) : { for name, v in var.volumes : "${member}/${name}" => merge(v, { member = member, name = coalesce(v.name, name) }) }]...)

  registrations = merge([for member in keys(var.members) : { for name, t in var.target_groups : "${member}/${name}" => { member = member, arn = t.arn, port = t.port } }]...)
}
