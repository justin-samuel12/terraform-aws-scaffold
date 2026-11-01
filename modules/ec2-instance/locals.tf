locals {
  tags = merge(var.tags, {
    Group         = var.group
    "Patch Group" = var.environment
  }, var.backup ? { Backup = "standard" } : {})

  standard  = var.protect ? {} : var.members
  protected = var.protect ? var.members : {}
  instances = merge(aws_instance.standard, aws_instance.protected)

  volumes = merge([for member in keys(var.members) : { for name, v in var.volumes : "${member}/${name}" => merge(v, { member = member, name = name }) }]...)

  registrations = merge([for member in keys(var.members) : { for name, t in var.target_groups : "${member}/${name}" => { member = member, arn = t.arn, port = t.port } }]...)
}
