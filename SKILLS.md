# Operating rules for AI assistants in this repository

This repository manages AWS infrastructure: the network hubs, every
environment's VPCs and workloads, IAM, DNS, storage and Lambda functions. A
careless command here takes down DNS, access, or compute for everything that
runs on it.

These rules are absolute. "It was a scratch copy", "it used local state",
"it reported zero changes" are **not** exceptions. They are exactly the
reasoning behind the outages these rules exist to prevent.


## What this is

Code is organised by region, then environment, then component:
`live/<region>/<environment>/<component>/`, each folder one stack with its own
state. Shared plumbing (the Transit Gateway hubs, IAM, DNS) is the `shared`
environment: `live/<region>/shared/` and `live/global/shared/`. The network (the
accounts, the state bucket, VPCs and subnets) is described in `config/`, which the
network team owns; everything else is configured beside its stack in `live/`.
Stacks are built from the modules in `modules/`, through the templates in
`templates/`.
Layout and reasoning: [docs/architecture.md](docs/architecture.md).

Status: scaffold. Until `config/` names real accounts and a state bucket,
nothing can be planned or applied.

It deploys no applications and applies nothing on merge.

## Invariants

Breaking one of these breaks a production guarantee.

**Every apply is human.** Nothing applies on merge. No pipeline holds
credentials that could. The assistant never runs one.

**State is per stack**, one state per `live/<region>/<environment>/<component>`
folder. That boundary is the blast radius. Do not merge stacks, do not reach
across environments.

**Dependencies flow one way.** Within an environment and region: network, then security groups, then endpoints
and load balancers, then keys and backups, then databases and storage, then
compute. Every environment may read `shared`; `shared` reads
no environment. Never introduce a cycle or a read from one environment into
another.

**Accounts and the state bucket exist before this repository runs.** It creates
neither. Each environment's account is written in `config/<region>.yml` and the
state bucket in `config/global.yml`; a stack without them refuses to run, and there is no
local state ([docs/configuration.md](docs/configuration.md)). Every stack is
pinned to its environment's account, so a plan cannot run with another
environment's credentials. Code holds no account IDs; only `config/` does.

**Inputs are typed and validated.** A value that does not match fails the plan;
nothing is read loosely or dropped silently.

**A module change reaches every environment at once.** Modules and templates
are sourced by local path, not by version, so a change to one shows up in every
stack that uses it on that stack's next plan. Review a module change as a change
to every environment, and plan each affected stack before applying any. Pinned,
tagged module versions come once the repository has a git remote to tag.

**Secrets are fetched at runtime, never rendered.** Not into `user_data`, not
into state, not into plan output, not onto a command line.

**There is no destroy target.** Removing infrastructure is a reviewed change to
the code, never a command.

## Best practice is the bar

This repository is built to current AWS and Terraform best practice. When a
request and best practice disagree, say so and explain the trade-off before
writing it.

Already built in, for every stack that uses the modules:

- **Every VPC records all its traffic**: flow logs, accepted and rejected, to
  CloudWatch Logs, kept 365 days.
- **Every VPC's default security group is empty**: no rules in or out. AWS does
  not allow deleting it, so emptying it is how it is disabled.
- **Spokes have no internet or NAT gateway**: they go out through the hub's
  egress VPC. Only a VPC with `public: true` gets a public tier.
- **Environments are isolated by hub route tables**: nothing joins one by
  default, and production is never reachable from `standard`.
- **The VPN accepts only IKEv2, AES-256, SHA-2 and Diffie-Hellman group 14 or
  higher**, and both tunnels log to CloudWatch.
- **Service roles trust only their service acting for this account**
  (`aws:SourceAccount`, `aws:SourceArn`), and grant only the actions they use,
  on only their own resources.
- **One kind of server**: every group of servers is a file in `compute`,
  whether or not a load balancer reaches it or CodeDeploy deploys it.
  CodeDeploy reaches only servers tagged with both its environment and its
  group.
- **Every resource is tagged** through `default_tags`, and every stack is pinned
  to its environment's account.
- **VPCs, subnets and Transit Gateways refuse replacement** (`prevent_destroy`):
  a plan that would rebuild one fails before anything changes.
- **The account baseline** blocks public S3 account-wide, encrypts every new
  EBS volume, blocks public snapshot sharing, and runs an access analyzer in
  every region in `config/`.
- **Data is encrypted with the environment's own keys**: customer-managed,
  multi-Region, rotated yearly, separate keys for live data and backups, kept in
  Terraform so their policies are reviewed.
- **Databases**: managed rotated passwords, TLS required, logs exported, 35-day
  backups, a final snapshot always, deletion protection.
- **Every database and file system is backed up by AWS Backup**, daily and
  monthly, into a locked vault copied to Oregon.
- **Every Session Manager session** is encrypted, logged to CloudWatch, closed
  after 20 idle minutes and capped at 8 hours; access to a host is a tunnel
  document granted by ARN, never SSH.
- **Every environment is patched** in its own maintenance window, security and
  critical patches only, a quarter of instances at a time.
- **Servers**: images pinned by ID, IMDSv2 only (hop limit 2), no SSH keys, no
  public addresses, encrypted disks, patched and backed up by tag. Every server
  has termination protection, and a new image or boot script never rebuilds
  one: a rebuild is a deliberate `-replace`, never a side effect of a plan.
  Extra disks are never destroyed by a plan. Chosen addresses come only from
  each subnet's reserved block.
- **Load balancers and WAF log every request** to the region's log buckets,
  which are encrypted, versioned, TLS-only and never destroyed by a plan.
- **Databases cannot reach the internet**: the `data` tier routes only
  `10.0.0.0/8`, to the hub.

Expected of everything added from here on:

- **Encryption at rest and in transit**: EBS, S3, RDS, logs and backups
  encrypted; S3 buckets block public access, keep versions and refuse non-TLS
  requests.
- **No long-lived credentials**: no IAM users or access keys; people come
  through Identity Center, workloads through roles.
- **Least privilege**: no `"*"` actions on `"*"` resources. Scope by resource
  ARN and, for service roles, by source account.
- **Instances**: IMDSv2 required, Session Manager instead of SSH, no public IP
  outside the public tier, no secrets in `user_data`.
- **Security groups**: one per workload, rules that reference other security
  groups rather than CIDRs where possible, and no `0.0.0.0/0` inbound except a
  public load balancer on 443.
- **Logs kept 365 days** unless there is a stated reason for another period.
- **Official providers, our own modules**: the only outside code is official
  HashiCorp providers (`hashicorp/aws`, `hashicorp/archive`), pinned in `.terraform.lock.hcl`. No
  community or third-party providers, and no module from the Terraform Registry
  or anywhere else, community or AWS-published (`terraform-aws-modules`,
  `aws-ia`). Every module lives in `modules/`, written and tested here.
- **Tests with every module**: what it builds, and at least one input it must
  refuse. `make check` passes before review.

## Never run these. Ever.

| Command | Why |
|---|---|
| `terraform apply` | Only a human applies. No flags, no directory, no exceptions. |
| `terraform destroy` | Same. |
| `state mv` / `state rm` / `state push`, or anything else that writes state | Mutates state. |
| `-auto-approve` | Removes the only confirmation that exists. |
| Any `make` target that applies | A wrapper does not make it safer. |
| `git push` (esp. `--force`) | Publishes. Irreversible for others. |
| `git commit` unless explicitly asked | The user commits their own work. |
| `git filter-repo`, `git reset --hard`, `git checkout --` on dirty files | Destroys work. |
| Any AWS `create-*`, `put-*`, `delete-*`, `update-*`, `associate-*` | Mutates cloud resources. |
| `aws sso login` / anything touching the user's credentials | Theirs to manage. |
| Switching to another AWS profile or role unasked | Use the identity the user names; an admin identity is theirs to choose. |

**A throwaway directory is not a justification.** The verb is what matters, not
the working directory. If a command's name implies mutation, do not run it.

## Read-only equivalents — use these instead

Evaluating locals, outputs, or data sources is the classic trap: `apply` gets
used where any of these would have worked:

```
terraform console                 # evaluate locals and expressions
terraform providers schema -json  # resource/attribute shapes
terraform validate                # syntax and types
terraform fmt -check
terraform test                    # module tests, against mocked providers
terraform show / state list       # inspect existing state, read-only
```

For AWS, only `describe-*`, `list-*`, `get-*`.

## terraform plan

`plan` is read-only against infrastructure, but it is **not** free:

- it needs credentials and reaches the provider API
- with state locking it takes a lock

Say what you are about to run and why, then let the user run it. Prefer
handing over the command to running it yourself.

## Announce before anything that changes something

Before any command that writes to disk outside the scratchpad, mutates state,
calls a cloud write API, or touches a git remote: say what it will do and wait.
Do not bundle it into a larger command block where it is easy to miss.

Documentation is the exception: it touches no infrastructure. Update it as part
of the change, unasked.

## Hand over, never apply

Write the change, run `make check`, then hand the plan and apply commands to
the user. Planning
and applying are theirs.

- `aws_route53_zone` for a private zone needs `lifecycle { ignore_changes = [vpc] }`
  or the plan disassociates every VPC and breaks internal DNS.
- Never set `force_destroy = true` on a hosted zone. Public zones hold records
  that exist nowhere else.
- A stack restructured without changing infrastructure uses `moved` blocks; the
  plan must show only "has moved to" lines and `0 to add, 0 to change, 0 to
  destroy`.

## Secrets

- Never print a secret value, even one already committed.
- Never put a credential in `user_data` — it is readable from instance
  metadata, `ec2:DescribeInstanceAttribute`, Terraform state, and on disk.
- Never pass a secret on a command line; `ps` is world-readable per user.
- A secret written to AWS by Terraform goes through a write-only argument
  (`value_wo`, `password_wo`), so it never reaches state.
- A secrets store is for things that grant access. Account IDs, VPC IDs and zone IDs are
  identifiers, not secrets, and belong in config where they are reviewable.

Full model: [SECURITY.md](SECURITY.md).

## Commits and pull requests

**No AI attribution in git history.** Commit messages, trailers, authors and
pull request descriptions name people, never tools:

- no `Co-Authored-By:` for an AI assistant (Claude, Copilot, ChatGPT or any other)
- no session links, "Generated with …" footers or tool signatures
- the author and committer are the person responsible for the change

An assistant that adds these by default must be told not to, and anything it
added is removed before pushing. A squash merge copies every commit message on
the branch into the main branch, so one stray trailer lands there permanently.

## Documentation

Docs go stale silently, and a stale doc is worse than a missing one — it gets
trusted.

**Updating the docs is part of the change, not a follow-up.** See
[CONTRIBUTING.md](CONTRIBUTING.md).

Do not describe a flag, target or input from memory or from another doc. Read
the implementation and describe what it does.

**Code carries no documentation, only references to it.** In scripts, the
`Makefile`, hooks and `.tf` files, a comment may state in one line *why* the
next few lines exist, and point to the doc that explains the rest:

```hcl
# The zip hash includes the file mode; fixing it keeps a different umask from looking like a code change.
```

Usage, option lists, examples, input shapes, rationale and history belong in
`docs/`. A comment that explains is a second home for a fact, and it drifts from
the first.

## If something has already gone wrong

State plainly what was run and what it changed. Do not minimise, do not lead
with reassurance, and do not run further commands to "check" without asking —
the user may be revoking credentials.
