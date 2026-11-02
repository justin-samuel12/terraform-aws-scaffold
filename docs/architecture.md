# Architecture

```mermaid
flowchart TB
  live["live/"]
  live --> global["global/shared/<br/><sub>account-wide: baseline · iam · dns · cloudfront</sub>"]
  live --> region["us-east-2/ · us-west-2/"]
  region --> shared["shared/<br/><sub>hub · logging · ecr · session-manager · documents</sub>"]
  region --> env["operations/ · production/ · staging/"]
  env --> stacks["network · security-groups · endpoints · keys · backups<br/>certificates · load-balancers · waf · databases · storage<br/>buckets · compute · records · access · patching · lambda"]

  classDef g fill:#f3f0ff,stroke:#6741d9,color:#25125e
  classDef s fill:#fff4e5,stroke:#e8590c,color:#5c2a00
  classDef e fill:#e8f1fb,stroke:#2f6fb3,color:#0b2545
  class global g
  class shared s
  class env,stacks e
```

## Layout

Code is organised by region, then environment, then component:
`live/<region>/<environment>/<component>`. Each folder is one stack with its own
state.

- **Region first**: everything running in a region sits together, which is how
  a regional outage, a regional DR test or a region's cost is looked at.
- **Environment second**: production in Ohio and its DR copy in Oregon are the
  same stacks with the same settings, under each region's `production/`.
- **`shared`** is the environment every other one uses: each region's hub under
  `live/<region>/shared/`, and account-wide IAM and DNS under
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

Hub and spoke, owned by us. One Transit Gateway hub per region, peered; each
environment is a spoke in its region. The hub is its own stack, separate from
operations: it rarely changes and every environment depends on it.

| Region | Hub | Spokes |
|---|---|---|
| us-east-2 (Ohio) | `live/us-east-2/shared/hub` | operations, production |
| us-west-2 (Oregon) | `live/us-west-2/shared/hub` | staging, production DR |

Ohio is the primary region: its hub in `config/us-east-2.yml` says `primary: true`, so it
requests the peering (the other hubs are applied first), is HQ's preferred path,
and is where `global` stacks run. Oregon is the disaster-recovery region.

The VPN to HQ terminates on both hubs. Spokes reach each other only
where hub route tables allow it. Modules, IP plan and routing: [network.md](network.md).

## One account, or one per environment

Both work, from the same code. With one account (`account_id` once in
`config/global.yml`), every environment, the hubs and the shared stacks live
together, and names carry the environment so nothing collides. With an account
per environment (`account_id` on its entry in `config/<region>.yml`), the hubs
stay in the shared account and share the network with the others:

```mermaid
flowchart LR
  subgraph shared["🔀 shared account (the hubs)"]
    tgw["Transit Gateway"]
    rules["resolver rules · prefix lists"]
    zones["hosted zones"]
    ram["RAM share network-01"]
    tgw & rules --> ram
  end
  subgraph env["🏭 an environment's account"]
    vpc["VPC + attachment"]
    recs["its servers, load balancers, databases"]
  end
  ram -->|"shared; accepted unless the<br/>Organization shares automatically"| env
  vpc -->|"attachment, accepted and routed<br/>by the hub's owner"| tgw
  vpc -->|"associated, after the zone's<br/>owner authorizes it"| zones
  recs -->|"records written in the hub's zones"| zones

  classDef s fill:#fff4e5,stroke:#e8590c,color:#5c2a00
  classDef e fill:#e8f1fb,stroke:#2f6fb3,color:#0b2545
  class tgw,rules,zones,ram s
  class vpc,recs e
```

What AWS lets only the hub's owner do, a stack does through its second
provider, `aws.hub`: the hub's account, with the `shared` environment's profile
(the same account in single-account mode, so nothing changes). That covers
accepting and routing the attachment, authorizing private zones, and writing
Route 53 records (records, certificate validation, compute's
`route53_records`). Whoever plans an environment's network, records,
certificates or compute in another account therefore needs profiles for both
accounts.

| | One account | An account per environment |
|---|---|---|
| Network | attachment routed directly | the hub shares the Transit Gateway, resolver rules and prefix lists through RAM (`network-01`); the hub's owner accepts and routes the attachment |
| Private zones | associated directly | authorized by the zone's owner, then associated |
| ECR | pulled directly | each repository lets the other accounts pull |
| Per-account settings | once: `global/shared/baseline`, `global/shared/iam`, each region's `shared/logging` and `shared/session-manager` | the same stacks again for each environment account: `global/<environment>/baseline`, `global/<environment>/iam`, `<region>/<environment>/logging`, `<region>/<environment>/session-manager` |

`organization_sharing: true` in `config/global.yml` says the accounts are in one
AWS Organization with RAM sharing turned on, so shares arrive without
invitations; leave it `false` and each environment account accepts the share
from its network stack.

Security group references across environments (`group:<environment>/<name>`)
work only between environments that share an account: a stack can only look
up groups its own account can see.

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
