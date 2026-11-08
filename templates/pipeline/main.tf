module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = abspath(local.config_dir)
}

module "pipeline_roles" {
  source = "../../modules/pipeline-roles"
  count  = length(local.problems) == 0 ? 1 : 0

  environment          = var.environment
  account_id           = local.account
  hub_account_id       = local.hub_account
  github_repository    = local.repository
  branch               = local.branch
  create_oidc_provider = local.create_oidc_provider
  state_bucket         = local.bucket
  state_key_format     = local.key_format
  duties               = { for name, d in local.duties : name => { components = d.components, actions = d.actions, uses = d.uses, roles = try(d.roles, []), across = try(d.across, []) } }
  other_environments   = [for e in local.environments : e if e != var.environment]
  hub_segments         = var.environment == "shared" ? {} : local.segments[var.environment]
  spokes               = var.environment == "shared" ? { for env in local.spokes : env => { account_id = local.accounts[env], hub_segments = local.segments[env] } } : {}
}
