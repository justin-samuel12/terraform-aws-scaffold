output "networks" {
  description = "\"<environment>/<region>\" -> CIDR, purpose, segment, propagation, zones, public tier, hub ASN, whether it is the primary hub, subnet CIDRs per tier, and each network tier's route."
  value       = local.networks

  # The rules every region file in config/ must meet -- docs/network.md.
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
    condition     = alltrue([for cidr in local.hq.cidrs : can(cidrnetmask(cidr))]) && (local.hq.ip_address == null || can(cidrhost("${local.hq.ip_address}/32", 0)))
    error_message = "hq in config/global.yml: cidrs must be a list of CIDRs, and ip_address an IPv4 address or empty."
  }
  precondition {
    condition     = length(local.layout_problems) == 0
    error_message = "The subnet layout is not usable: ${join("; ", local.layout_problems)}."
  }
  precondition {
    condition     = length(local.problems.shape) == 0
    error_message = "Unknown or misspelt keys (a network has account_id, team, cidr, segment and public; a hub has account_id, team, cidr, amazon_side_asn and primary): ${join(", ", [for key in local.problems.shape : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.cidr) == 0
    error_message = "cidr must be a network address, a /16 for a network and a /20 for a hub: ${join(", ", [for key in local.problems.cidr : local.labels[key]])}."
  }
  precondition {
    condition     = length(local.problems.segment) == 0
    error_message = "segment must be restricted, standard or shared: ${join(", ", [for key in local.problems.segment : local.labels[key]])}."
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

output "hq" {
  description = "HQ, from config/global.yml: its public IP and BGP ASN for the VPN (ip_address null until known) and its address ranges, for security group rules."
  value       = local.hq
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
  description = "DNS from config/global.yml: whether HQ may resolve AWS private names (inbound), domain -> HQ DNS server IPs to forward to, and the private hosted zones every VPC attaches to."
  value       = local.dns

  precondition {
    condition     = alltrue(flatten([for domain, targets in local.dns.forward : concat([can(regex("^[a-z0-9.-]+$", domain)) && length(targets) > 0], [for ip in targets : can(cidrhost("${ip}/32", 0))])]))
    error_message = "dns.forward in config/global.yml: each domain needs at least one DNS server IP."
  }
}
