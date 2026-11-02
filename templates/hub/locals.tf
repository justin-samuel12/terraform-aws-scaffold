locals {
  network = module.ip_plan.networks["shared/${var.region}"]
  tables  = ["restricted", "standard", "shared"]

  # Everything private the hub routes: 10.0.0.0/8, and HQ's ranges outside it, which the resolver must reach to forward DNS.
  private_ranges = concat([module.ip_plan.internal_cidr], [for c in module.ip_plan.hq.cidrs : c if !startswith(c, "10.")])

  # The resolver endpoints need the hub layout's dns tier.
  dns_tier = contains(keys(local.network.subnets), "dns")

  # Peering: the primary hub requests one to every other region's hub. Each table reaches the other region's ranges by the same
  # rules as at home; peering attachments do not propagate, so these are static routes.
  peer_regions = local.network.primary ? sort([for key, n in module.ip_plan.networks : split("/", key)[1] if n.purpose == "egress" && split("/", key)[1] != var.region]) : []
  reach        = { restricted = ["restricted", "shared"], standard = ["standard", "shared"], shared = ["restricted", "standard", "shared"] }
  cidrs = {
    for region in concat([var.region], local.peer_regions) : region => {
      for segment in local.tables : segment => sort([for key, n in module.ip_plan.networks : n.cidr if split("/", key)[1] == region && n.segment == segment])
    }
  }

  # Every other account with an environment in this region gets the network shared with it: the Transit Gateway, the resolver
  # rules and the prefix lists. Keys come from config/, so a plan knows them before anything exists.
  share_accounts = sort(distinct([
    for key, n in module.ip_plan.networks : n.account_id
    if split("/", key)[1] == var.region && n.purpose == "spoke" && n.account_id != "" && n.account_id != local.network.account_id
  ]))
  share_resources = merge(
    { "transit-gateway" = module.transit_gateway.transit_gateway_arn },
    { for name in keys(module.ip_plan.prefix_lists) : "prefix-list/${name}" => module.prefix_list.arns[name] },
    local.dns_tier ? { for domain in keys(module.ip_plan.dns.forward) : "resolver-rule/${domain}" => module.route53_resolver[0].rule_arns[domain] } : {},
  )
}
