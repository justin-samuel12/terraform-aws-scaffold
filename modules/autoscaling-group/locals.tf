locals {
  name = "${var.environment}-${var.name}"

  # Provider default tags never reach instances an Auto Scaling group launches, so they are stamped on through the launch template.
  tags = merge(data.aws_default_tags.current.tags, var.tags, {
    Name       = var.name
    Group      = var.name
    PatchGroup = var.environment
  }, var.backup ? { Backup = "standard" } : {})
}
