locals {
  tags        = try(data.aws_default_tags.current.tags, {})
  environment = try(local.tags["Environment"], "")
  component   = try(local.tags["Component"], "")
  duties      = yamldecode(file(var.duties_file))
  owners      = [for name, d in local.duties : name if contains(d.components, local.component)]
  duty        = length(local.owners) == 1 ? local.owners[0] : null
  path        = "/deployed/"
}
