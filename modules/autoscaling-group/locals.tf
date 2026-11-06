locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  name = "${var.environment}-${var.name}"

  tags = merge(data.aws_default_tags.current.tags, var.tags, {
    Name       = "${local.name_prefix}${var.name}"
    Server     = var.name
    Group      = var.name
    PatchGroup = var.environment
  }, var.backup ? { Backup = "standard" } : {})
}
