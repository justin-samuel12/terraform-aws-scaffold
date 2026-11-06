locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "


  rules = merge([
    for name, g in var.groups : merge([
      for direction in ["ingress", "egress"] : {
        for r in g[direction] : "${name}/${direction}/${r.ip_protocol}/${coalesce(r.from_port, 0)}-${coalesce(r.to_port, 0)}/${coalesce(r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.referenced_security_group_id)}" => merge(r, { owner = name, direction = direction })
      }
    ]...)
  ]...)
}
