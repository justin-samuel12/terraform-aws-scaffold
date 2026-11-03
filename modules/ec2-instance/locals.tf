locals {
  tags = merge(var.tags, {
    Group      = var.group
    PatchGroup = var.environment
  }, var.backup ? { Backup = "standard" } : {})

  volumes = merge([for member in keys(var.members) : { for name, v in var.volumes : "${member}/${name}" => merge(v, { member = member, name = name }) }]...)

  registrations = merge([for member in keys(var.members) : { for name, t in var.target_groups : "${member}/${name}" => { member = member, arn = t.arn, port = t.port } }]...)
}
