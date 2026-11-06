output "networks" {
  description = "\"<environment>/<region>\" -> CIDR, purpose, connectivity, segment, propagation, zones, public tier, hub ASN, whether it is the primary hub, where its region's hub has resolver endpoints (inbound, outbound) and which domains it forwards (domains), subnet CIDRs per tier, and each network tier's route."
  value       = local.networks

  precondition {
    condition     = length(local.files.names) == 0
    error_message = "Region files are named after an AWS region, config/<region>.yml; these are not: ${join(", ", local.files.names)}."
  }
  precondition {
    condition     = length(local.files.shape) == 0
    error_message = "Each region file has zones, hub, and optionally vpcs, and nothing else; check ${join(", ", local.files.shape)}."
  }
  precondition {
    condition     = length(local.files.zones) == 0
    error_message = "zones must list at least 2 distinct availability zone IDs of one region, numbered az1 to az6, such as use2-az1: ${join(", ", local.files.zones)}."
  }
  precondition {
    condition     = length(local.files.reserved) == 0
    error_message = "shared is the hub's environment and cannot be under vpcs: ${join(", ", local.files.reserved)}."
  }
  precondition {
    condition     = try(local.global.hq, null) == null
    error_message = "hq in config/global.yml is now sites: every network reached over a VPN is a named site under sites, each with enabled, ip_address, bgp_asn, cidrs and forward."
  }
  precondition {
    condition     = (try(local.global.sites, null) == null || can(keys(local.global.sites))) && alltrue([for name, site in local.site_files : can(regex("^[a-z][a-z0-9-]*$", name)) && can(keys(site)) && alltrue([for k in try(keys(site), []) : contains(local.site_keys, k)])])
    error_message = "sites in config/global.yml: named sites, each with enabled, ip_address, bgp_asn, cidrs and forward (sites: { office: { ip_address: ..., bgp_asn: ..., cidrs: [...] } }); a site's name is lowercase with hyphens."
  }
  precondition {
    condition     = alltrue([for name, site in local.site_files : try(site.enabled, null) == null || can(tobool(site.enabled))])
    error_message = "sites in config/global.yml: enabled is true or false; leave it out for true."
  }
  precondition {
    condition     = alltrue([for name, site in local.all_sites : alltrue([for cidr in site.cidrs : can(cidrnetmask(cidr))]) && alltrue([for ip in site.ip_addresses : can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", ip)) && can(cidrhost("${ip}/32", 0))]) && (length(site.ip_addresses) == 0 || site.bgp_asn != null)])
    error_message = "sites in config/global.yml: each site's cidrs are CIDRs, its ip_address one IPv4 address or a list of them (one per link), and a site with an ip_address needs its bgp_asn."
  }
  precondition {
    condition     = length(distinct(flatten([for name, site in local.sites : site.ip_addresses]))) == length(flatten([for name, site in local.sites : site.ip_addresses]))
    error_message = "sites in config/global.yml: an ip_address is listed twice; each address is one VPN device, in one site."
  }
  precondition {
    condition     = length(local.directory_problems) == 0
    error_message = "The directory cannot be built as written: ${join("; ", local.directory_problems)}."
  }
  precondition {
    condition     = length(local.resolver_problems) == 0
    error_message = "The DNS resolver is not placed so it can work: ${join("; ", local.resolver_problems)}."
  }
  precondition {
    condition     = length(local.site_overlaps) == 0
    error_message = "sites in config/global.yml: a site's range overlaps a network in AWS, so traffic to it could not be told apart: ${join("; ", local.site_overlaps)}."
  }
  precondition {
    condition     = length(local.layout_problems) == 0
    error_message = "The subnet layout is not usable: ${join("; ", local.layout_problems)}."
  }
  precondition {
    condition     = length(local.problems.shape) == 0
    error_message = "Unknown or misspelt keys (a network has account_id, team, cidr, segment, public and connectivity; a hub has account_id, team, cidr, amazon_side_asn, primary and security_group_referencing): ${join(", ", [for key in local.problems.shape : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.cidr) == 0
    error_message = "cidr must be a network address, a /16 for a network and a /20 for a hub: ${join(", ", [for key in local.problems.cidr : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.connectivity) == 0
    error_message = "connectivity is transit_gateway (the default: through the region's hub) or peering (its own NAT and VPC peering, routes from the network stack's config/route-table/): ${join(", ", [for key in local.problems.connectivity : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.segment) == 0
    error_message = "segment must be restricted, standard or shared for a network on the hub, and is left out for one with connectivity: peering: ${join(", ", [for key in local.problems.segment : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.referencing) == 0
    error_message = "security_group_referencing must be true or false: ${join(", ", [for key in local.problems.referencing : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.public) == 0
    error_message = "public must be true or false: ${join(", ", [for key in local.problems.public : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.asn) == 0
    error_message = "amazon_side_asn must be a private ASN, 64512 to 65534: ${join(", ", [for key in local.problems.asn : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.primary) == 0
    error_message = "primary must be true or false: ${join(", ", [for key in local.problems.primary : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.conflicts.account) == 0
    error_message = "An environment has one account in every region; these differ between region files: ${join(", ", local.conflicts.account)}."
  }
  precondition {
    condition     = length(local.conflicts.team) == 0
    error_message = "An environment has one team in every region; these differ between region files: ${join(", ", local.conflicts.team)}."
  }
  precondition {
    condition     = length(local.conflicts.primary) == 0
    error_message = "Exactly one hub must say primary: true; check ${join(", ", [for key in local.conflicts.primary : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.conflicts.asn_reused) == 0
    error_message = "Each hub needs its own amazon_side_asn; these are used twice: ${join(", ", local.conflicts.asn_reused)}."
  }
  precondition {
    condition     = length(local.conflicts.outside) == 0
    error_message = "These ranges fall outside the internal range the hubs route (internal_cidr): ${join(", ", [for key in local.conflicts.outside : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.conflicts.overlap) == 0
    error_message = "These ranges overlap: ${join(", ", local.conflicts.overlap)}."
  }
}

output "internal_cidr" {
  description = "The summary range routed between VPCs through the hubs."
  value       = local.internal_cidr
}

output "sites" {
  description = "The enabled sites, from config/global.yml: site name -> its VPN devices' public IPs, one per link (none until known: no VPN), its BGP ASN, the address ranges behind it, and the domains forwarded to its DNS servers. A site with enabled: false is left out entirely."
  value       = local.sites
}

output "site_cidrs" {
  description = "Every enabled site's address ranges, together."
  value       = local.site_cidrs
}

output "directory" {
  description = "The AWS Managed Microsoft AD the primary hub builds, from directory in config/global.yml (name, short_name, edition, description), or null while it is absent or enabled: false."
  value       = local.directory
}

output "primary_region" {
  description = "The region of the hub that says primary: true."
  value       = length(local.conflicts.primary) == 0 ? one([for key, n in local.networks : split("/", key)[1] if n.primary]) : null
}

output "prefix_lists" {
  description = "Prefix list name -> its entries (cidr, description), from config/global.yml."
  value       = local.prefix_lists

  precondition {
    condition = alltrue(flatten([
      for name, entries in local.prefix_lists : concat([can(regex("^[a-z][a-z0-9-]*$", name))], [for e in entries : can(cidrnetmask(e.cidr)) && trimspace(e.description) != ""])
    ]))
    error_message = "prefix_lists in config/global.yml: names are lowercase with hyphens, and every entry needs a CIDR and a description."
  }
}

output "dns" {
  description = "DNS from config/global.yml: whether the sites may resolve AWS private names (inbound), domain -> DNS server IPs to forward to (every enabled site's forward, together), the private hosted zones in the hub that every VPC attaches to (private_zones, the private domain itself among them), the public domains (public_domains), where a name is written only when its file names the zone, and the private domain under which each environment has its own zone."
  value       = local.dns

  precondition {
    condition     = (try(local.global.dns.public_domain, null) == null || can(tolist(local.global.dns.public_domain))) && length(distinct(local.dns.public_domains)) == length(local.dns.public_domains) && alltrue([for d in local.dns.public_domains : can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", d))])
    error_message = "dns.public_domain in config/global.yml: a list of domain names, each once (- example.com)."
  }

  precondition {
    condition     = (try(local.global.dns.private_domain, null) == null || can(tostring(local.global.dns.private_domain))) && (local.dns.private_domain == null || can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", coalesce(local.dns.private_domain, "-"))))
    error_message = "dns.private_domain in config/global.yml: one domain name (example.internal), not a list."
  }

  precondition {
    condition     = !endswith(coalesce(local.dns.private_domain, "-"), ".local")
    error_message = "dns.private_domain in config/global.yml: not .local, which laptops resolve by multicast instead of DNS; use .internal, reserved for private names."
  }

  precondition {
    condition     = length(local.dns.resolve_all) == 0 || (local.dns.inbound && local.dns.private_domain != null && alltrue([for env in local.dns.resolve_all : contains(local.environment_names, env)]))
    error_message = "dns.resolve_all_private in config/global.yml: environments in config/, and it needs dns.inbound: true and a private_domain, since their VPCs ask the hub's inbound resolver."
  }

  precondition {
    condition     = try(local.global.dns.forward, null) == null
    error_message = "dns.forward in config/global.yml has moved: a domain is forwarded by the site whose DNS servers answer it, as sites.<site>.forward, so removing the site removes its forwarding too."
  }

  precondition {
    condition     = length(distinct(local.site_forward_domains)) == length(local.site_forward_domains)
    error_message = "sites in config/global.yml: a domain is forwarded by more than one enabled site; each domain goes to one site's DNS servers."
  }

  precondition {
    condition     = alltrue(flatten([for domain, targets in local.dns.forward : concat([can(regex("^[a-z0-9.-]+$", domain)) && length(targets) > 0], [for ip in targets : can(cidrhost("${ip}/32", 0))])]))
    error_message = "sites.<site>.forward in config/global.yml: each domain needs at least one DNS server IP."
  }
}

output "zones" {
  description = "Environment -> its private zone (<environment>.<private_domain>, in its own account): where its names go when a file names no zone."
  value       = local.zones
}

output "accounts" {
  description = "Every account in config/: hub (each region's hub account) and environments (each environment's account), from its own account_id or config/global.yml's."
  value = {
    hubs         = { for key, n in local.networks : split("/", key)[1] => n.account_id if n.purpose == "egress" }
    environments = { for env, accounts in { for key, n in local.networks : split("/", key)[0] => n.account_id... if n.purpose == "spoke" } : env => accounts[0] }
  }
}

output "organization_sharing" {
  description = "true: the accounts are in one AWS Organization with RAM sharing turned on, so shares reach them without invitations. false: each account accepts the hub's share. organization_sharing in config/global.yml."
  value       = try(tobool(local.global.organization_sharing), false)
}

output "codedeploy" {
  description = "CodeDeploy defaults from config/global.yml (codedeploy:), which each application can override in its compute stack's deployments/<application>.yml: deployment_group_names (default master, development and adhoc, one per branch deployed from), deployment_config_name (default CodeDeployDefault.OneAtATime), auto_rollback_configuration.events (default DEPLOYMENT_FAILURE); bootstrap = { repository, commit_id }, a GitHub revision deployed and stopped once when the last of those groups is created, so CodeDeploy's GitHub connection is in place; null for none."
  value = {
    groups                 = [for g in try(local.global.codedeploy.deployment_group_names, ["master", "development", "adhoc"]) : tostring(g)]
    deployment_config_name = tostring(try(local.global.codedeploy.deployment_config_name, "CodeDeployDefault.OneAtATime"))
    rollback_events        = [for e in try(local.global.codedeploy.auto_rollback_configuration.events, ["DEPLOYMENT_FAILURE"]) : tostring(e)]
    bootstrap = try(local.global.codedeploy.bootstrap.repository, null) == null ? null : {
      repository = tostring(local.global.codedeploy.bootstrap.repository)
      commit_id  = tostring(local.global.codedeploy.bootstrap.commit_id)
    }
  }
}
