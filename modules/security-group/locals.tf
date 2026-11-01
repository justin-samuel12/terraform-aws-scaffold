locals {
  default_egress = [
    { description = "Internal traffic, through the hub", protocol = "-1", from_port = null, to_port = null, group = null, cidr = var.internal_cidr, prefix_list = null },
    { description = "HTTPS out, through the hub's egress", protocol = "tcp", from_port = 443, to_port = 443, group = null, cidr = "0.0.0.0/0", prefix_list = null },
  ]

  # One entry per rule, keyed by what it allows rather than its position, so reordering a file changes nothing.
  rules = merge([
    for name, g in var.groups : merge(
      { for r in g.ingress : "${name}/ingress/${r.protocol}/${coalesce(r.from_port, 0)}-${coalesce(r.to_port, 0)}/${coalesce(r.group, r.cidr, r.prefix_list)}" => merge(r, { owner = name, direction = "ingress" }) },
      { for r in coalesce(g.egress, local.default_egress) : "${name}/egress/${r.protocol}/${coalesce(r.from_port, 0)}-${coalesce(r.to_port, 0)}/${coalesce(r.group, r.cidr, r.prefix_list)}" => merge(r, { owner = name, direction = "egress" }) },
    )
  ]...)
}
