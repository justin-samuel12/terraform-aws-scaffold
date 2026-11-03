variable "config_file" {
  description = "This machine's config: which AWS profile to use per environment. null = ~/.config/infra/hashicorp-terraform.config, the file make setup writes."
  type        = string
  default     = null
}

variable "config_dir" {
  description = "The repository's config folder; null = config/ at the repository root. Tests point it at their own."
  type        = string
  default     = null
}

locals {
  path_parts = split("/", abspath(path.root))
  # Every stack is exactly three folders under live/, so its live/ is the fourth folder from the end (a clone under a folder of
  # its own called live is still read correctly).
  live_index      = length(local.path_parts) - 4
  location        = local.path_parts[local.live_index + 1]
  environment     = local.path_parts[local.live_index + 2]
  component       = local.path_parts[local.live_index + 3]
  repository_dir  = local.path_parts[local.live_index - 1]
  repository_root = join("/", slice(local.path_parts, 0, local.live_index))

  config_dir     = abspath(coalesce(var.config_dir, "${local.repository_root}/config"))
  primary_region = one([for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") if try(yamldecode(file("${local.config_dir}/${name}")).hub.primary, false) == true])
  region         = local.location == "global" ? local.primary_region : local.location
  region_file    = "${local.config_dir}/${local.region}.yml"
  region_config  = try(yamldecode(file(local.region_file)), {})
  # A global stack runs in the primary region, but its environment may run only elsewhere: its settings come from the first
  # region file that has it (an environment in two regions has one account and team, which the IP plan checks).
  regions_with_environment = sort([for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") if name != "global.yml" && can(yamldecode(file("${local.config_dir}/${name}")).vpcs[local.environment])])
  settings_file            = local.location == "global" && local.environment != "shared" && !contains(local.regions_with_environment, local.region) && length(local.regions_with_environment) > 0 ? "${local.config_dir}/${local.regions_with_environment[0]}.yml" : local.region_file
  settings                 = try(local.environment == "shared" ? local.region_config.hub : yamldecode(file(local.settings_file)).vpcs[local.environment], {})
  global_config            = try(yamldecode(file("${local.config_dir}/global.yml")), {})
  # The Repository tag: config/global.yml's repository, so every clone tags alike; else the folder the clone is in.
  repository     = try(tostring(local.global_config.repository), local.repository_dir)
  own_account    = try(tostring(local.settings.account_id), "")
  account_id     = local.own_account != "" ? local.own_account : try(tostring(local.global_config.account_id), "")
  account_source = local.own_account != "" ? local.settings_file : "${local.config_dir}/global.yml"
  team           = try(tostring(local.settings.team), null)
  pinned         = can(regex("^[0-9]{12}$", local.account_id))

  # The region's hub: the account that owns the Transit Gateway, the zones and the shared network. The same as this stack's in
  # single-account mode; another account when environments have their own -- docs/architecture.md.
  hub_own_account = try(tostring(local.region_config.hub.account_id), "")
  hub_account     = local.hub_own_account != "" ? local.hub_own_account : try(tostring(local.global_config.account_id), "")
  hub_pinned      = can(regex("^[0-9]{12}$", local.hub_account))
  cross_account   = local.pinned && local.hub_pinned && local.account_id != local.hub_account

  machine_file   = pathexpand(coalesce(var.config_file, "~/.config/infra/hashicorp-terraform.config"))
  machine_text   = fileexists(local.machine_file) ? file(local.machine_file) : ""
  machine_set    = trimspace(join("\n", [for line in split("\n", local.machine_text) : line if !startswith(trimspace(line), "#")])) != ""
  machine_config = yamldecode(local.machine_set ? local.machine_text : "{}")
  profile        = try(local.machine_config.profiles[local.environment], null)
  hub_profile    = try(local.machine_config.profiles["shared"], local.profile)
}
