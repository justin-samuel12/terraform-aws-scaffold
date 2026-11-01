# Architecture

## Layout

Code is organised by region, then environment, then component:
`live/<region>/<environment>/<component>`. Each folder is one stack with its own
state.

- **Region first**: everything running in a region sits together, which is how
  a regional outage, a disaster-recovery test or a region's cost is looked at.
- **Environment second**: production and its disaster-recovery copy in a second
  region are the same stacks with the same settings, under each region's
  `production/`.
- **`shared`** is the environment every other one uses: each region's hub under
  `live/<region>/shared/`, and account-wide IAM, DNS and KMS under
  `live/global/shared/`. `global` takes a region's place for stacks that are not
  regional; they run in the primary region.

Every stack is three levels deep, so every stack's path names its region,
environment and component, and its state key is that path.

Who changes what follows the folders. `config/` (accounts, the state bucket, zones,
the subnet layout, hubs and VPCs) belongs to the network team or the AWS
administrators. Everything else, security groups, compute and databases, is
configured in `.yml` files beside the stack that builds it, and belongs to that
environment's owners. In a repository, CODEOWNERS enforces this: `/config/` for
the network team, and `/live/*/production/` for production's owners.

## Network

Hub and spoke. One Transit Gateway hub per region, peered when there are two;
each environment is a spoke in its region. The hub is its own stack, separate
from every environment: it rarely changes and every environment depends on it.

The example is one region and one environment:

| Region | Hub | Spokes |
|---|---|---|
| us-east-1 | `live/us-east-1/shared/hub` | development |

A typical next step is staging and production beside development, and a second
region (`config/us-west-2.yml`, its own `shared/hub`) holding production's
disaster-recovery copy. The hub whose file says `primary: true` is built first,
requests the peering, is HQ's preferred path, and is where `global` stacks run.

The VPN to HQ terminates on every hub. Spokes reach each other only
where hub route tables allow it. Modules, IP plan and routing: [network.md](network.md).

## Diagram

[diagram.md](diagram.md) is generated, never drawn: `make diagram` reads the VPCs
from `config/` through `modules/ip-plan`, and the stacks from `live/`. A stack
counts as built once it has `.tf` files of its own; everything else in the IP
plan shows as planned. Below the diagram, it lists every VPC's subnets with
their zone, CIDR and `Subnet` tag, in address order. The pre-commit hook refuses
a commit that leaves it stale.

## Dependencies

Within an environment and region: network, then security groups, then endpoints
and load balancers, then keys and backups, then databases and storage, then
compute. Every
environment may read `shared`; `shared` reads no environment.
