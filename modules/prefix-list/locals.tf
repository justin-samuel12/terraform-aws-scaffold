locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "
}
