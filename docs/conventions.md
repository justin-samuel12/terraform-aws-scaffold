# Conventions

## Versions

| | Constraint |
|---|---|
| Terraform | `>= 1.12.0` |
| AWS provider | `~> 6.63` |
| tflint AWS ruleset | `0.49.0`, in `.tflint.hcl` |
| Our modules and templates | none yet: sourced by local path, so a change reaches every stack on its next plan |

Every stack, template and module declares the Terraform and provider
constraints. Only stacks commit `.terraform.lock.hcl`; modules and templates do
not pin providers.

## Modules

Only official HashiCorp providers (`hashicorp/aws`, and `hashicorp/archive` to
zip Lambda code), pinned in each stack's
`.terraform.lock.hcl`; no community or third-party providers. Every module is
ours, in `modules/`, sourced by local path: none comes from the Terraform
Registry or any other outside source, community or AWS-published. Nothing in
the repository depends on code it does not control beyond the official
provider.

## Names

A resource has two names, and they follow different rules.

**Its name in AWS** (a load balancer's, a bucket's, a role's, a queue's, a
security group's `name`, a log group's, a KMS alias) is lowercase with hyphens,
because AWS restricts the characters and many of these names cannot change
without rebuilding the resource. They stay as they are; the files and stacks
refer to things by them.

**Its `Name` tag** is what the AWS console shows in its Name column, and is
written for a person reading it: the environment in title case, a spaced
hyphen, then what the thing is.

```
<Environment> - <What>
```

The environment comes from the provider's `Environment` default tag, so every
module writes its own `Name` tags without being told the environment; hub and
global stacks are `shared`, so theirs read `Shared - …`. A module run without
that default tag (its tests, against a mocked AWS) writes only `<What>`.

Pieces of the network are named by what they are, in words. Things that have a
name of their own (a file's name, or a name input) keep it as written, without
the environment in front of it a second time.

| Resource | `Name` tag |
|---|---|
| VPC | `Staging - VPC` |
| Subnet | `Staging - Private Subnet AZ1` (tier in title case, `DMZ` and `DNS` in capitals; the zone from the zone ID's last part) |
| Route table | `Staging - Private Route Table AZ1` |
| Network ACL | `Staging - Data Network ACL` |
| Internet gateway | `Staging - Internet Gateway` |
| NAT gateway, and its address | `Staging - NAT Gateway AZ1`, `Staging - NAT Gateway AZ1 Address` |
| Flow log, its log group and role | `Staging - Flow Logs` |
| The VPC's default security group | `Staging - Default Security Group (unused)` |
| A VPC's attachment to the hub | `Staging - Transit Gateway Attachment` |
| Peering connection | `Staging - Peering to operations` (the peering file's name) |
| Transit Gateway | `Shared - Transit Gateway` |
| Its route tables | `Shared - Transit Gateway Restricted`, `… Standard`, `… Shared` |
| Hub-to-hub peering | `Shared - Transit Gateway Peering to us-east-2`, and `… Peering from us-west-2` on the other side |
| VPN | `Shared - Corporate VPN 203.0.113.10`, `Shared - Corporate Customer Gateway 203.0.113.10`, `Shared - Corporate VPN Tunnel Logs 203.0.113.10`: the site leads, the device's address follows, one set per link |
| Route 53 Resolver | `Shared - DNS Resolver`, `… DNS Resolver Inbound`, `… DNS Resolver Outbound`, `… DNS Forward example.internal` |
| RAM share of the hub | `Shared - Network Share` |
| ECS and EKS clusters | `Staging - ECS Cluster`, `Staging - ECS Exec Logs`; `Staging - EKS Cluster`, `Staging - EKS Cluster Role`, `Staging - EKS Node Role` |
| Security group | `Staging - services-lb` |
| Load balancer, target group, listener | `Staging - public`, `Staging - services-api`, `Staging - public-443` |
| Server, its disks | `Staging - ocp01`, `Staging - ocp01-root`, `Staging - ocp01-data` |
| Anything else with a name | `Staging - <its name>`: `Staging - orders` (a queue), `Staging - data` (a key), `Staging - payments-api` (a service) |

Nothing finds a resource by its `Name` tag, so it can be reworded without
breaking a lookup. Stacks find each other's resources by the stable tags below,
or by the resource's name in AWS.

In code, names are generic. What a thing is for (its environment, region,
purpose) is carried by tags and by where its stack sits in `live/`, never by a
module's or a resource's name:

| Kind | Rule | Examples |
|---|---|---|
| Modules | The AWS service, not its role | `vpc`, `transit-gateway`, `transit-gateway-peering`, `vpn` |
| Resources in code | The resource type; never `this` or `that` | `aws_vpc.vpc`, `aws_subnet.subnets["private-usw2-az1"]`, `aws_ec2_transit_gateway.transit_gateway` |
| Transit Gateway route tables | The isolation level, not an environment | `restricted`, `standard`, `shared` |

Lowercase throughout in code and AWS names; underscores in code, hyphens in AWS
names.

## Files

HashiCorp's standard module structure, in modules, templates and stacks alike:

| File | Holds |
|---|---|
| `main.tf` | resources and module calls, or the template's core when it splits out a concern |
| `data.tf` | data sources |
| `locals.tf` | local values |
| `variables.tf` | input variables |
| `outputs.tf` | outputs |
| `versions.tf` | Terraform and provider version constraints |

A file holds only its kind: no data source, local or output in `main.tf`, and
`make lint` refuses a data source anywhere but `data.tf`. A template that builds several
concerns of its own keeps each in a file named after it, beside `main.tf`:
`templates/network/` has `transit-gateway.tf`, `dns.tf` and `peering.tf`. A module with no
resources (`ip-plan`) has no `main.tf`. A stack that calls a template has only
`main.tf` and `outputs.tf` of its own; its inputs come from `context.tf`.

Every stack also has its own copy of each shared file in `live/common/`, under
conventional names that never collide with a stack's own files. They are real
files, not links, so a zip, a Windows checkout or any archive tool keeps them
intact. `make backends` writes them, and the pre-commit hook and `make check`
refuse a copy that differs from `live/common/`. Edit the file in `live/common/`,
then run `make backends`.

| Shared file | Holds |
|---|---|
| `context.tf` | who and where the stack is: environment, region and component from `stack.tf`; its account and team from `config/<region>.yml`; this machine's profile (Cloud Posse's `context.tf` convention, so it keeps its variables and locals together) |
| `providers.tf` | the AWS provider, pinned to the environment's account; refuses to plan without one |
| `versions.tf` | Terraform and provider versions |

A stack that also needs another region (CloudFront's certificates and WAF in
us-east-1) declares that provider in a file named after the region,
`us-east-1.tf`, with the same account pin, profile and tags as `providers.tf`.

Every stack also has two generated files of its own, written by `make backends`:

- `stack.tf` names the stack: its location, environment and component. The
  stack's account, region, tags and state all follow from it. Before
  anything is planned, Terraform compares it with the folder the stack is in and
  stops if they differ, so a copied or moved folder can never deploy into the
  stack it came from, or share its state.
- `backend.tf` holds the state bucket, its region, and the stack's own key
  (shaped by `state.key` in `config/global.yml`; by default the stack's name).

Never edit either by hand; the pre-commit hook refuses one that disagrees. To
move a stack on purpose, move the folder, run `make backends`, and review the
new `stack.tf` and `backend.tf` together with a state move.

## Tags

Applied through the provider's `default_tags`, so every resource carries them:

| Tag | Example |
|---|---|
| `ManagedBy` | `terraform` |
| `Environment` | `production` |
| `Component` | `network` |
| `Repository` | `repository` in `config/global.yml`, so every clone tags alike; else the folder the clone is in |
| `Team` | `platform`, the environment's `team` in `config/<region>.yml`; left off when unset ([configuration](configuration.md#config)) |

A few more are set by the modules, so stacks can find one another's resources
without depending on a display name:

| Tag | On | Example | For |
|---|---|---|---|
| `Tier` | subnets, their route tables and network ACLs | `data` | finding all of a tier's subnets |
| `Subnet` | subnets and their route tables | `data-az1` | naming exactly one subnet in an environment's VPC, by tier and the zone ID's last part; an instance is placed by it |
| `Segment` | Transit Gateway route tables | `standard` | a network or another hub finding a route table by isolation level |
| `Key` | security groups; load balancers' target groups | `services-lb`; `staging-services-api` | a stack finding a group by its file's name, or a target group by its load balancer's name and its own |
| `Server` | servers | `ocp01` | the server's name: its host name, its DNS record, its placement |

Security groups also carry `Kind`, which every group's file sets: one of
`load-balancer`, `server`, `database`, `client` or `endpoint`
([security groups](security-groups.md)).

Tags are how resources are found and filtered: in the console, in cost
reports, and in one stack looking up another (a network finds its region's
Transit Gateway by `Component = hub`, and a stack its environment's VPC by
`Environment` and `Component = network`).

Tags your organization requires go in each stack's `default_tags`
(`live/common/providers.tf`), so every resource carries them.

`ManagedBy`, `Environment`, `Component`, `Repository` and `Team` are the
platform's: the pipeline's permissions keep environments and duties apart by
`Environment` and `Component`, so no `.yml` file may set them
([blueprints](blueprints.md#what-no-file-can-change)).

## IAM

Every IAM role, instance profile and customer managed policy a stack creates is
under the path `/deployed/`, and every role carries the permission boundary of
the duty that deploys it, `terraform-boundary-<environment>-<duty>`, from
`modules/role-boundary`. A module that creates roles takes `role_boundary`, and a
template passes it on. The pipeline may manage and pass only roles under
`/deployed/` that carry its boundary, so a role that does not would fail at
apply; `make lint` refuses it first. The one exception is the role Systems
Manager requires by name and path, listed for the `services` duty in
`templates/duties.yml`.

## Inputs

Two formats, nothing else of our own:

- **`.yml` for configuration**: settings a person adjusts, in small files, one
  per thing, so a change is one file in review. A VPC's range, an
  environment's owner, a machine's profiles and state location. Terraform reads
  them and checks every field. Always `.yml`, never `.yaml`.
- **`.tf` for Terraform**, including what a script generates for it (each
  stack's `backend.tf`).

No JSON. The exceptions are files whose tool dictates the format:
`.tflint.hcl`, `.gitleaks.toml` and Terraform's own `.terraform.lock.hcl`.

Typed variables with validation. A value that does not match fails the plan;
nothing is read with a fallback that hides a mistake.

## Dependencies

Inside a module, order comes from references: a resource that uses another's
attribute waits for it. `depends_on` is added only where AWS needs an order no
reference shows, with a one-line comment saying why: a NAT gateway after the
internet gateway, routes after the hub attachment, bucket policies after the
public access block, rules on old versions after versioning, anything handed an
IAM role after the role's permissions are attached (the `iam-role` module's
outputs wait for them), and log groups before the service that would otherwise
create them without retention.

Between stacks there is no `depends_on`: a stack looks up what it needs by name
or tag, and its plan fails, naming what is missing, until the stack that builds
it has been applied. That is what enforces the order in
[architecture](architecture.md#dependencies).

## Checks

Before a change is reviewed, `make check` runs every check below in order,
with no credentials and no state, and stops at the first that fails:

| Check | On its own | Also in the pre-commit hook |
|---|---|---|
| Formatting | `make fmt-check` | yes, when `.tf` files are staged |
| Lint, with the AWS ruleset | `make lint` | yes, when `.tf` files are staged and `tflint` is installed |
| Tests, against a mocked AWS | `make test` | no: they take minutes |
| Every stack validates | `make validate-all` (one: `make validate STACK=...`) | no |
| Every stack's files plan | `make check-files` | no |
| Every example plans | `make check-examples` | no |
| Backends match `config/` | `bin/backends --check` | yes |
| Secrets | `gitleaks` | yes; the commit is refused without it |
| Diagram up to date | `bin/diagram --check` | yes |
| Every role a stack creates carries its boundary | `make lint` | no |
| Pipeline policies, linted and modeled; Terraform scanned | `make security` (parliament and Trivy, pinned) | no: in CI |
| Workflows commented, valid, and passing `actionlint` | `bin/workflows check` | no: in CI |
| GitHub's settings match `config/global.yml` | `bin/github verify` | no: needs GitHub access |
