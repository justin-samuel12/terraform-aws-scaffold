# Security groups

Each environment's security groups are a stack of their own, between its network
and anything that uses them: `live/<region>/<environment>/security-groups/`. A
rule change plans on its own, never touching routing or servers.

## One file per group

The file name is the group's name. Adding a group is adding a file.

```yaml
# live/us-east-1/development/security-groups/web.yml
description: web servers
ingress:
  - description: HTTPS from the web load balancer
    port: 443
    from:
      - web-lb
  - description: Metrics between web servers
    ports:
      - 9090
      - 9100-9110
    from:
      - self
  - description: SSH from the ops tier
    port: 22
    from:
      - tier:ops
```

| Key | Meaning |
|---|---|
| `description` | What the group is for. Required |
| `load_balancer` | `true` for a public load balancer's group: the only kind that may accept `internet` |
| `ingress` | Rules for traffic in. Each has a `description`, a `port` or `ports`, an optional `protocol`, and `from` |
| `egress` | Rules for traffic out, with `to` instead of `from`. Leave it out for the default: internal traffic (`10.0.0.0/8`) and HTTPS out |

`ports` is a list of ports and ranges (`9100-9110`). `protocol` is `tcp` (the
default), `udp`, `icmp` or `all` (no ports).

## Sources, never raw addresses

`from` and `to` name what may connect, so a file copies between environments
and regions unchanged:

| Source | Stands for |
|---|---|
| a group's name | that security group in the same stack |
| `self` | this group's own members |
| `tier:<name>` | that tier's subnets in this environment's VPC, from `config/` |
| `network:<environment>` | that environment's whole VPC in this region |
| `list:<name>` | a managed prefix list from `prefix_lists` in `config/global.yml`, built in the region's hub: named groups of people or hosts, such as `list:staff-team` |
| `hq` | HQ's ranges, `hq.cidrs` in `config/global.yml` |
| `internet` | `0.0.0.0/0`; only on TCP 443, and only to a `load_balancer` group |

## What the plan refuses

A rule without a description, an unknown key, ports outside 0 to 65535 or
reversed, a rule with no ports for a protocol other than `all`, a group name
that is not in the stack, a tier the VPC does not have, an environment with no
VPC in the region, a `list:` that `config/global.yml` does not define, `hq`
while `hq.cidrs` is empty, and `internet` on anything
but TCP 443 to a load balancer group.

## How it is built

The `security-group` module creates every group and one resource per rule
(`aws_vpc_security_group_ingress_rule`, `aws_vpc_security_group_egress_rule`).
Each rule is keyed by what it allows, so reordering a file changes nothing. The
`security-groups` template reads the files, turns sources into addresses from
`config/`, and finds the VPC by its tags.

## Prefix lists

Groups of addresses that are about people or hosts rather than a tier or a VPC
(the office and VPN networks, the domain controllers) are named once, by
the network team, in `config/global.yml`:

```yaml
prefix_lists:
  staff-team:
    - cidr: 10.10.70.0/24
      description: Corporate wired
    - cidr: 10.10.80.0/24
      description: Corporate wireless
```

Each region's hub builds them as AWS managed prefix lists (the `prefix-list`
module), with room for five more entries each. A rule uses one as
`list:staff-team`; changing a list's entries changes every rule that uses it,
with no edit to any group file. Each list's maximum size counts against the
rule limit of every security group that uses it.
