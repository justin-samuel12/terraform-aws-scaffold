# Accounts

Every environment names its AWS account in `config/`, and nothing else in the
repository does: no module, template or stack holds an account ID. The same code
runs with everything in one account, with every environment in its own, or
anything between, and moving from one to another is a change to `config/` and a
state move, not a redesign.

## Who owns what

| Responsibility | Where it is set | Built by | Applied by |
|---|---|---|---|
| The organization: accounts, organization policies (SCPs), delegated administrators, the organization's trail | Outside this repository, in the management account | Nobody here; nothing here assumes it exists | The organization's administrators |
| The network hub of a region: Transit Gateway, its route tables, VPN, peering between hubs, the resolver, the egress VPC | `hub.account_id` in `config/<region>.yml` | `live/<region>/shared/hub` | `terraform-apply-shared-hub` |
| The shared zones and their DNS writers | The primary hub's account | `live/global/shared/dns` | `terraform-apply-shared-hub` |
| Shared services: image repositories, log buckets, Session Manager, the account baseline (Access Analyzer, EBS encryption) | The hub's account, and each environment's for its own | `shared` and environment stacks of the `services` duty | `terraform-apply-<environment>-services` |
| An environment's network: its VPC, endpoints, private zones, its attachment | `vpcs.<environment>.account_id` in `config/<region>.yml` | `live/<region>/<environment>/network`, `endpoints`, `global/<environment>/zones` | `terraform-apply-<environment>-network`, and the hub's side through `terraform-network-<environment>` |
| An environment's workloads: servers, containers, databases, queues, keys, certificates, records | The same | The environment's other stacks | `terraform-apply-<environment>-workload` |
| IAM roles written as files | The account of the stack | `global/<environment>/iam` | `terraform-apply-<environment>-iam` |
| The pipeline's own roles, its OIDC provider, and the permission boundaries | The account of the environment | `global/<environment>/pipeline` | A person, never the pipeline |
| The state bucket | `state.bucket` in `config/global.yml` | `make bootstrap` | A person |
| Security and audit: CloudTrail, GuardDuty, Security Hub, a log archive | Not built here | | The organization, or a later stack |

`account_id` set once in `config/global.yml` is every environment's account
unless an environment or hub sets its own.

## Duties

A duty is a set of components that change together and are deployed by one role.
`templates/duties.yml` names each duty's components, the actions its role may
take, and what it may *use* that another duty owns (a subnet to launch a server
into, a key to encrypt with). Every component is in exactly one duty, and a stack
whose component is in none is refused.

| Duty | Components | In | May change |
|---|---|---|---|
| `hub` | `hub`, `dns` | `shared` | Its Transit Gateway, route tables, VPN, peering, resolver, zones, the egress VPC |
| `services` | `baseline`, `cloudfront`, `documents`, `domain-join`, `ecr`, `logging`, `session-manager` | any | Those services, and the account's EBS defaults; nothing in a VPC |
| `iam` | `iam` | any | Roles, policies and instance profiles under `/deployed/`, each with its boundary |
| `network` | `network`, `endpoints`, `zones` | spokes | Its own VPC and what is in it, its endpoints and private zones, its attachment to the hub; the hub's side only through `terraform-network-<environment>` |
| `workload` | everything else | spokes | Servers, containers, databases, queues, keys, certificates, records, its security groups; never the VPC's structure or the hub |
| `pipeline` | `pipeline` | any | Applied by a person; the pipeline has no role for it |

### What every apply role is refused

Whatever its duty, in every account, an apply role may never:

- change a `terraform-*` role, policy or instance profile, or the GitHub OIDC
  provider: its own permissions, its trust, or another pipeline role's;
- create a role without its duty's permission boundary, change a role's
  boundary to any other, remove one, change a role that carries another duty's
  boundary, attach `AdministratorAccess`, `IAMFullAccess` or `PowerUserAccess`, or
  pass a role that is not under `/deployed/` to a service;
- assume any role but the narrow ones its duty uses (`terraform-network-<environment>`
  and `dns-<environment>`);
- create users, access keys, console passwords or other long-lived credentials;
- touch the organization or the account's settings;
- change the state bucket's policy, versioning, encryption, lifecycle or public
  access, or delete an old version of a state file;
- read or write any state but its own stacks', or any stored plan but its own,
  or overwrite a claim on a plan;
- touch a bucket that does not start with its environment's name;
- stop, delete or change a CloudTrail trail;
- change a resource tagged with another environment, or create one tagged with
  another environment, and use one only if it is tagged `shared`;
- remove an `Environment` or `Component` tag, or retag a resource into another
  environment or duty;
- delete or change the servers, databases, keys, secrets and similar resources
  listed in `must_be_tagged` when they carry no `Environment` tag;
- create the resources listed in `created_tagged` without an `Environment` tag;
- change a resource tagged with another duty's component, or create one for
  another duty;
- and, unless it is the hub's, change a Transit Gateway, its route tables or
  routes, attachments' acceptance, VPN or peering; unless it is a network's,
  change a VPC's subnets, routes, network ACLs, gateways, flow logs or endpoints.

Every role a stack creates carries `terraform-boundary-<environment>-<duty>`. A
boundary only caps what the role's own policies grant, and a resource policy
naming the role can add to it, so what makes this one work is its explicit
denies, which nothing can override. It refuses every IAM change (except the
instance profile and service-linked role EKS Auto Mode manages), passing or
assuming a role outside `/deployed/`, the state bucket, the organization, the
trail, central and spoke network changes, changing anything tagged with another
environment or `shared`, using or reading the data of another environment, and
other environments' buckets. Its `Allow *` is deliberate: an allow-list would
have to name everything every application may ever call, and would be widened
until it meant nothing.

Apply roles keep broad actions in their own services (`ec2:*`, `rds:*`, and so
on) on purpose: Terraform needs most of each service's API across create, read,
update and delete, and those lists change with every provider release. What is
narrow is what those actions can touch, by the denies above.

The evidence, in `modules/deployment-policies/tests`, comes from independent
sources. `requests.yml` lists requests that must be refused and that must be
allowed. A model of IAM evaluation written in Terraform decides them under
`make test`. `bin/iam-check` then has an open-source simulator
(`@cloud-copilot/iam-simulate`, pinned) decide the same requests, intersecting a
boundary with an administrator's identity policy, and checks every condition key
on a named action against AWS's published service data, and lints every policy
with parliament. `bin/iam-check --aws` adds AWS itself: Access Analyzer and the
policy simulator, read-only, with credentials for any account. None of the
offline checks is AWS: they cannot show what a service does through its
service-linked role, and the live test in
[operations](operations.md#checking-the-permissions-in-a-test-account) covers
that.

## One account, or many

| Arrangement | In `config/` | What keeps environments apart |
|---|---|---|
| One account for everything | `account_id` in `global.yml` only | Tags and duties only; set `pipeline.dedicated_accounts: []` to accept it |
| The hub and shared services in one account, each environment in its own | `hub.account_id` and each `vpcs.<environment>.account_id` | Accounts, then tags and duties within each |
| Production alone, the rest together | Production's own `account_id`; the others share one | Production by account; the others by tags and duties |
| A network account, a shared-services account, and workload accounts | One account per hub, per environment | Accounts |

Each environment's provider is pinned to its account (`allowed_account_ids`), so
a profile for the wrong account fails before anything is planned; a stack
deploys only to a region with a file in `config/`, and only where `config/` puts
its environment, so it never falls back to another account.

### Sharing an account

Environments in one account are kept apart by their `Environment` and
`Component` tags, by bucket names, and by the duties. What that does and does not
give you:

| | One account | Own accounts |
|---|---|---|
| Another environment's tagged resources, for services that check tags | Refused | Refused |
| Another environment's state and stored plans | Refused | Refused |
| Another environment's buckets | Refused by name | Refused |
| Route 53 records: no AWS tag support; a workload role can change any record in the account's zones | **Not isolated** | Isolated |
| Actions with no resource-level permission (some `logs`, `sns`, `cloudwatch`, `ecr` calls, and creating some resources) | **Not isolated** | Isolated |
| A resource with no `Environment` tag, made by hand or by a service | Only the `must_be_tagged` actions are refused; **others are not** | Isolated |
| A resource with no tags being claimed by tagging it (AWS cannot tell that from tag-on-create, except for servers) | **Possible** | Isolated |
| Describe and list calls showing another environment's configuration | **Allowed** | Isolated |
| Service quotas and account-wide settings | **Shared** | Separate |

Numbers for each service, from AWS's own reference, can be regenerated from
`https://servicereference.us-east-1.amazonaws.com/`: the share of write actions
that accept `aws:ResourceTag` runs from none for Route 53 to all for `sqs` and
`secretsmanager`. Environment names may not begin with another's name and a
hyphen (the pipeline refuses `staging` next to `staging-dr`), because buckets are
told apart by that prefix.

So `pipeline.dedicated_accounts` in `config/global.yml`, `production` by
default, lists the environments that must have an account of their own, and the
pipeline stack refuses to build roles while one shares its account. Taking an
environment out of that list accepts these limits for it, in a reviewed change.

## Across accounts

| Crossing | How | Narrowed to |
|---|---|---|
| A spoke reaches its hub's Transit Gateway | The hub shares it through RAM (`network-01`); without an Organization, each account accepts the share | The accounts with an environment on that hub |
| The hub accepts, associates and announces a spoke's attachment | The spoke's network role assumes `terraform-network-<environment>` in the hub's account | That environment's attachments, its own segment, the segments it may announce to, its private zones |
| A spoke writes its names in a shared public zone | Its apply role, or a person, assumes `dns-<environment>` in the primary hub's account; roles under `/deployed/` cannot | Its own names, by `route53:ChangeResourceRecordSetsNormalizedRecordNames` |
| Planning reads those zones | The plan and propose roles assume `terraform-dns-read-<environment>` | Reading the zones only |
| A stack reads and writes its state | The bucket policy from `make bootstrap` | Each account to its own environments' keys and stored plans |

## A parent organization's network

When another organization runs a region's Transit Gateway and shares it, name it
in that region's hub instead of building one:

```yaml
# config/us-east-2.yml
hub:
  transit_gateway:
    owner: parent
    id: tgw-0123456789abcdef0
    share_arn: arn:aws:ram:us-east-2:999999999999:resource-share/parent-network
```

The hub then builds no gateway, route tables, VPN or peering of its own; its VPC
and every spoke in the region attach to the parent's gateway, accepting its share
when `share_arn` is set; and acceptance, route tables and propagation are the
parent's, so `terraform-network-<environment>` gets no Transit Gateway
permission there. DNS, endpoints and everything inside the VPCs stay here.
`owner: self`, the default, is this repository's own gateway.

## Adding an account

1. Create the account, in the Organization if there is one, and give a person a
   way in: an IAM Identity Center permission set, or the organization's access
   role.
2. Put its ID in `config/`: an environment's `account_id`, or a hub's.
3. `make bootstrap` again: the bucket policy lets the account reach its own keys.
4. `make backends`, then `make plan` the environment's `pipeline` stack and apply
   it as a person. It creates the OIDC provider if it is the first environment in
   the account, the roles, and the boundaries every later stack needs.
5. With the hub's account set and RAM sharing not through an Organization,
   apply `global/shared/pipeline` again for its `terraform-network-<environment>`
   role, and the hub of each region the environment is in, so it shares with the
   new account.
6. Apply the environment's stacks in the order `make order` gives.

Nothing in an account is assumed: a new account has no OIDC provider, no
boundary, no share, until these steps make them, and every stack's plan says
which one is missing.
