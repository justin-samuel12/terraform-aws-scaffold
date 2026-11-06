locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  network = module.ip_plan.networks["shared/${var.region}"]
  tables  = ["restricted", "standard", "shared"]

  private_ranges = concat([module.ip_plan.internal_cidr], [for c in module.ip_plan.site_cidrs : c if !startswith(c, "10.")])

  dns_tier  = contains(keys(local.network.subnets), "dns")
  directory = local.network.primary && local.dns_tier && module.ip_plan.directory != null

  peer_regions = local.network.primary ? sort([for key, n in module.ip_plan.networks : split("/", key)[1] if n.purpose == "egress" && split("/", key)[1] != var.region]) : []
  reach        = { restricted = ["restricted", "shared"], standard = ["standard", "shared"], shared = ["restricted", "standard", "shared"] }
  cidrs = {
    for region in concat([var.region], local.peer_regions) : region => {
      for segment in local.tables : segment => sort([for key, n in module.ip_plan.networks : n.cidr if split("/", key)[1] == region && n.segment == segment])
    }
  }

  share_accounts = sort(distinct([
    for key, n in module.ip_plan.networks : n.account_id
    if split("/", key)[1] == var.region && n.purpose == "spoke" && n.connectivity == "transit_gateway" && n.account_id != "" && n.account_id != local.network.account_id
  ]))
  share_resources = merge(
    { "transit-gateway" = module.transit_gateway.transit_gateway_arn },
    { for name in keys(module.ip_plan.prefix_lists) : "prefix-list/${name}" => module.prefix_list.arns[name] },
    local.dns_tier ? { for domain, arn in module.route53_resolver[0].rule_arns : "resolver-rule/${domain}" => arn } : {},
  )
}
