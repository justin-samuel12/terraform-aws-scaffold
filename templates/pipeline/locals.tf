locals {
  config_dir     = startswith(var.config_path, "/") ? var.config_path : "${path.module}/${var.config_path}"
  global         = try(yamldecode(file("${local.config_dir}/global.yml")), {})
  region_names   = sort([for f in fileset(local.config_dir, "*.yml") : trimsuffix(f, ".yml") if f != "global.yml"])
  regions        = { for r in local.region_names : r => try(yamldecode(file("${local.config_dir}/${r}.yml")), {}) }
  environments   = distinct(concat(["shared"], sort(distinct(flatten([for r in local.regions : keys(try(r.vpcs, {}))])))))
  spokes         = [for e in local.environments : e if e != "shared"]
  global_account = try(tostring(local.global.account_id), "")

  accounts = {
    for env in local.environments : env => coalesce(concat(
      [for r in local.region_names : try(tostring(env == "shared" ? local.regions[r].hub.account_id : local.regions[r].vpcs[env].account_id), "")],
      [local.global_account, "unset"],
    )...)
  }
  owners               = { for a in distinct(values(local.accounts)) : a => [for e in local.environments : e if local.accounts[e] == a][0] }
  account              = try(local.accounts[var.environment], "unset")
  hub_account          = local.accounts["shared"]
  create_oidc_provider = try(local.owners[local.account] == var.environment, false)

  hub_accounts = { for r in local.region_names : r => coalesce(try(tostring(local.regions[r].hub.account_id), ""), local.global_account, "unset") }

  all_duties = yamldecode(file("${path.module}/../duties.yml"))
  duties = {
    for name, d in local.all_duties : name => d
    if name != "pipeline" && contains([var.environment == "shared" ? "shared" : "spokes", "any"], d.environments)
  }

  segments = {
    for env in local.spokes : env => {
      for key, n in module.ip_plan.networks : split("/", key)[1] => { segment = n.segment, propagates_to = n.propagates_to }
      if split("/", key)[0] == env && n.connectivity == "transit_gateway" && n.segment != null && n.transit_gateway.owner == "self"
    }
  }

  pipeline_keys      = ["github_repository", "branch", "dedicated_accounts", "approvals", "reviewers"]
  pipeline           = try(local.global.pipeline, {})
  repository         = try(tostring(local.pipeline.github_repository), "")
  branch             = try(tostring(local.pipeline.branch), "")
  dedicated_accounts = try([for e in local.pipeline.dedicated_accounts : tostring(e)], ["production"])
  bucket             = try(tostring(local.global.state.bucket), "")
  key_format         = try(tostring(local.global.state.key), "{region}/{environment}/{component}")

  sharing = {
    for env in local.dedicated_accounts : env => [for other in local.environments : other if other != env && local.accounts[other] == local.accounts[env]]
    if contains(local.environments, env) && try(local.accounts[env], "unset") != "unset"
  }
  hub_regions = distinct(flatten([for env in local.spokes : keys(local.segments[env])]))

  problems = concat(
    [for k in try(keys(local.pipeline), ["?"]) : "config/global.yml: pipeline takes ${join(", ", local.pipeline_keys)}; ${k} is not one of them" if !contains(local.pipeline_keys, k)],
    local.repository == "" ? ["config/global.yml: pipeline.github_repository is the GitHub repository, owner/name, whose workflows deploy"] : [],
    local.branch == "" ? ["config/global.yml: pipeline.branch is the protected branch that plans are proposed from"] : [],
    local.bucket == "" ? ["config/global.yml: state.bucket is empty; make bootstrap creates the bucket and writes its name"] : [],
    contains(local.environments, var.environment) ? [] : ["${var.environment} is not an environment in config/: no region file has it under vpcs"],
    can(regex("^[0-9]{12}$", local.account)) ? [] : ["no 12-digit account_id for ${var.environment} in config/: its roles live in its account"],
    can(regex("^[0-9]{12}$", local.hub_account)) ? [] : ["no 12-digit account_id for the hub in config/: each network's hub role lives there"],
    [for env, others in local.sharing : "${env} shares account ${local.accounts[env]} with ${join(" and ", others)}. The pipeline's limits keep environments apart by their Environment and Component tags, which do not cover untagged resources or services without tag-based permissions (docs/accounts.md#sharing-an-account). Give ${env} its own account, or take it out of pipeline.dedicated_accounts in config/global.yml to accept that" if length(others) > 0],
    [for pair in setproduct(local.environments, local.environments) : "environments ${pair[0]} and ${pair[1]} cannot both exist: buckets are kept apart by the environment at the start of their names, and ${pair[1]}'s name starts with ${pair[0]}-" if startswith(pair[1], "${pair[0]}-")],
    [for e in local.environments : "state.bucket ${local.bucket} starts with ${e}-: that environment's roles manage buckets by that prefix, so the state bucket needs another name" if startswith(local.bucket, "${e}-")],
    [for r in local.hub_regions : "the ${r} hub is in account ${local.hub_accounts[r]}, not the shared environment's ${local.hub_account}: the network roles are made in the shared environment's account, so every hub that spokes attach to must be in it" if local.hub_accounts[r] != local.hub_account],
  )
}
