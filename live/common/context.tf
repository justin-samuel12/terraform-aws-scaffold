variable "config_file" {
  description = "This machine's config: which AWS profile to use per environment. null = ~/.config/infra/<repository folder>.yml, the file make setup writes."
  type        = string
  default     = null
}

variable "config_dir" {
  description = "The repository's config folder; null = config/ at the repository root. Tests point it at their own."
  type        = string
  default     = null
}

locals {
  path_parts      = split("/", abspath(path.root))
  live_index      = index(local.path_parts, "live")
  location        = local.path_parts[local.live_index + 1]
  environment     = local.path_parts[local.live_index + 2]
  component       = local.path_parts[local.live_index + 3]
  repository      = local.path_parts[local.live_index - 1]
  repository_root = join("/", slice(local.path_parts, 0, local.live_index))

  config_dir     = abspath(coalesce(var.config_dir, "${local.repository_root}/config"))
  primary_region = one([for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") if try(yamldecode(file("${local.config_dir}/${name}")).hub.primary, false) == true])
  region         = local.location == "global" ? local.primary_region : local.location
  region_file    = "${local.config_dir}/${local.region}.yml"
  region_config  = try(yamldecode(file(local.region_file)), {})
  settings       = try(local.environment == "shared" ? local.region_config.hub : local.region_config.vpcs[local.environment], {})
  account_id     = try(tostring(local.settings.account_id), "")
  team           = try(tostring(local.settings.team), null)
  pinned         = can(regex("^[0-9]{12}$", local.account_id))

  machine_file   = pathexpand(coalesce(var.config_file, "~/.config/infra/${local.repository}.yml"))
  machine_text   = fileexists(local.machine_file) ? file(local.machine_file) : ""
  machine_set    = trimspace(join("\n", [for line in split("\n", local.machine_text) : line if !startswith(trimspace(line), "#")])) != ""
  machine_config = yamldecode(local.machine_set ? local.machine_text : "{}")
  profile        = try(local.machine_config.profiles[local.environment], null)
}
