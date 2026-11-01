# Configuration

## Before anything runs

This repository builds inside AWS accounts it does not create. **Every AWS
account** the environments run in must exist first, made by whoever owns the AWS
Organization, with service control policies (SCPs) that allow what this
repository builds: the regions in `config/`, Transit Gateway, site-to-site VPN,
internet and NAT gateways, and VPC flow logs.

The accounts are written into `config/`, then `make bootstrap` creates the
state bucket ([below](#the-state-bucket-make-bootstrap)). Until both are in
place nothing runs: `bin/tf` refuses every command that needs state, and a plan
refuses a stack whose environment has no account. Apart from the bootstrap's
first few minutes, there is no local state and no fallback.

## config/

`config/global.yml` holds what every region shares: the state bucket and the
subnet layout every VPC uses ([network](network.md#ip-plan)):

```yaml
# config/global.yml, the state part
state:
  bucket: example-terraform-state
  region: us-east-1
  replica_region: us-west-2
  key: "{region}/{environment}/{component}"
```

`key` shapes every stack's state key, with `{region}` (or `global`),
`{environment}`, `{component}` and `{account_id}` (the environment's account)
filled in per stack, and `/terraform.tfstate` added. The default gives
`us-east-1/development/network/terraform.tfstate`. To follow an organization's
standard instead, change this one line, for example
`aws/{account_id}/{environment}/{region}-{component}`, and run `make backends`.
`bin/backends` refuses a key without `{environment}` and `{component}`, and any
key that would give two stacks the same state. Decide it before the first
apply: changing a key afterwards means moving each stack's state.

Then one file per region, named after it, with everything about that region: its
zones, its hub, and every environment's VPC there.

```yaml
# config/us-east-1.yml
zones:
  - use1-az1
  - use1-az2
  - use1-az4
hub:
  account_id: "333333333333"
  team: network
  cidr: 10.40.0.0/20
  amazon_side_asn: 64512
  primary: true
vpcs:
  development:
    account_id: "222222222222"
    team: platform
    cidr: 10.41.0.0/16
    segment: standard
    public: true
  production:
    account_id: "111111111111"
    team: platform
    cidr: 10.43.0.0/16
    segment: restricted
    public: true
```

| Key | Meaning |
|---|---|
| `hq`, `prefix_lists`, `dns` (in `global.yml`) | HQ's VPN address, BGP ASN and ranges; named address groups for security group rules ([security groups](security-groups.md#prefix-lists)); DNS forwarding between AWS and HQ ([network](network.md#dns-with-hq)), and the private hosted zones every VPC attaches to ([global](global.md#dns)) |
| `state.bucket`, `state.region`, `state.replica_region`, `state.key` (in `global.yml`) | The one S3 bucket holding every stack's state (`make bootstrap` fills it in), the region it lives in, the region it is replicated to (optional), and the shape of each stack's key (default: its path, such as `us-east-1/development/network/terraform.tfstate`) |
| `zones` | The availability zones every VPC in the region spans, by zone ID: at least two, numbered `az1` to `az6`. A zone ID is the same physical zone in every account, unlike a name such as `us-east-1a`, which AWS shuffles per account. Each tier gets one subnet per zone, named with its zone ID (`vpc-01-private-use1-az1`). Adding a zone only adds subnets; removing one is refused until done on purpose ([network](network.md#adding-and-removing-zones)) |
| `hub` | The `shared` environment in this region: the Transit Gateway hub and its egress VPC ([network](network.md#ip-plan)) |
| `vpcs.<environment>` | That environment's VPC in this region ([network](network.md#ip-plan)) |
| `account_id` | The only account the environment's stacks may run in. Required, quoted: unquoted, YAML reads `012345678901` as a number and drops the leading zero |
| `team` | Becomes the `Team` tag on everything the environment builds. Optional; without it the plan warns |

An environment with VPCs in two regions has the same `account_id` and
`team` in both files; the plan refuses them if they differ. Stacks under a
`global` folder run in the region whose hub says `primary: true`.

The files are committed and reviewed like code: an account, a range or an owner
changes in a pull request, never on one person's machine.

## Setting up: `make setup`

```bash
make setup
```

A guided setup that takes you as far as you can go without creating anything
in AWS, and stops there:

1. **Prerequisites**, below.
2. **Your AWS profiles**: it asks each one which account it is (read-only), so
   it can offer the right account and profile at each question.
3. **`config/` and the stacks** (`bin/configure`, which you can also run on its
   own): the primary region and its zones (looked up read-only when you are
   logged in), the shared account and hub, each environment's account, team,
   CIDR (suggested from the IP plan), segment and public tier, an optional
   second region for disaster recovery, the state bucket, and your office's
   VPN. For each new environment it asks whether to start with empty stacks or
   a copy of an existing environment's files, and for a removed one whether to
   delete its stacks. It shows the whole change, a diff of `config/` and every
   folder it will create, move or delete, and asks before writing. Then it
   writes every `backend.tf`, regenerates the diagram, and offers to check
   every stack's files against a mocked AWS.
4. **This machine's profiles** for each environment (below), and read-only
   checks of the state bucket if it exists.
5. **The next step**: add the accounts once they exist, then `make bootstrap`.

Every answer defaults to what is there now, so running it again changes only
what you change. Without a terminal (CI) it asks nothing and only checks.

### Prerequisites

It checks the prerequisites (Terraform 1.12 or later, AWS CLI v2, `jq`, `yq` v4
and `gitleaks` required; `tflint` optional) and stops if one is missing.
Homebrew does not carry `tflint`; install it from its GitHub release, checked
against the release's checksums:

```bash
d=$(mktemp -d) && cd "$d" \
  && gh release download v0.64.0 --repo terraform-linters/tflint --pattern tflint_darwin_arm64.zip --pattern checksums.txt \
  && grep ' tflint_darwin_arm64.zip$' checksums.txt | shasum -a 256 -c - \
  && unzip -q tflint_darwin_arm64.zip && install -m 755 tflint ~/.local/bin/tflint
```

On an Intel Mac use `tflint_darwin_amd64.zip`. `tflint --init` then downloads the
AWS ruleset pinned in `.tflint.hcl`. It
creates the shared provider cache and installs the git hooks once the folder is
a git repository.

It then reads `config/` and reports each environment's account and the state
bucket, flagging any not filled in yet. Finally it matches your
AWS profiles to the accounts: it asks each profile on the machine which account
it is (`sts get-caller-identity`, read-only; profiles you are not logged in to
are skipped) and offers the matching one for each environment. It warns if you
choose a profile for the wrong account. With the `shared` environment's profile
it then checks the state bucket, read-only: that it exists, that versioning is
on (so an overwritten or deleted state can be recovered), that default
encryption is on, and that it is replicated to another region. It warns rather
than fails. With no bucket yet, it says to run `make bootstrap`. A rerun offers your current choices as defaults, shows the
result and asks before writing; the previous file is kept as a dated backup.

Without a terminal (CI) it runs the checks and asks nothing.

## This machine's profiles

The only thing that differs from one person to the next is which AWS profile
they log in with. `make setup` writes it to `$INFRA_CONFIG`, else
`~/.config/infra/<repository folder name>.yml`, readable by its owner only and
never committed. Stacks read the same file themselves, so it applies with or
without `bin/tf`:

```yaml
profiles:
  shared: example-shared
  development: example-development
```

An environment without a profile uses whatever credentials are active
(`AWS_PROFILE`, an instance role, a CI role). Either way the stack is pinned to
the account in `config/`, so the wrong credentials fail the plan rather than
build in the wrong account.

## The state bucket: `make bootstrap`

```bash
make bootstrap
```

Creates the one S3 bucket every stack keeps its state in, in the shared
account (the primary hub's `account_id`), with the shared environment's
profile from `make setup`:

- named `state.bucket` from `config/global.yml`, or
  `terraform-state-<account>-<region>` when that is empty;
- versioned, encrypted, never public, refusing anything not over TLS, old
  versions kept a year, and never destroyed by a plan;
- replicated to `state.replica_region` when it is set, so state survives a
  regional outage.

The bucket's own stack (`bootstrap/`) starts on local state, because nothing
else can exist first. Once the bucket exists, the script moves that state into
the bucket (`bootstrap/terraform.tfstate`), writes the bucket's name into
`config/global.yml` and every stack's `backend.tf`, and keeps the emptied local
file as `terraform.tfstate.pre-migration` (ignored by git). It shows the plan
and asks before creating anything. Run again, it plans any change to the bucket
from its state in the bucket.

An existing bucket is never taken over: set `state.bucket` to it and
`make setup` checks that it is versioned, encrypted and replicated.

## Checking files without credentials: `make check-files`

```bash
make check-files                                  # every stack
make check-files ONLY="us-east-1/development/apps" # one or more
```

Plans every stack's own `.yml` files through its template against a mocked
AWS that answers like the real one: no credentials, no state, no accounts
needed yet (blank account IDs are filled with placeholders for the check). It
catches what a real plan would refuse in your files, a misspelt key, a missing
image, two routes on one host, before anyone logs in. `make check` runs it with
the tests, formatting, linting and validation.

## Running Terraform

```bash
make init STACK=us-east-1/development/network
make plan STACK=us-east-1/development/network
```

`make help` lists every target. The targets run `bin/tf`, which can also be
called directly: `bin/tf live/us-east-1/development/network plan`.

Before Terraform runs, `bin/tf` checks that the stack's region file has a quoted
12-digit account for the environment, that `global.yml` names the state bucket,
that the stack's `backend.tf` matches it, and on `init` that the bucket exists
(`s3api head-bucket`, read-only). It refuses `destroy`, `force-unlock` and the `state` commands that rewrite state;
those are run by hand, deliberately. `fmt`, `validate` and `init -backend=false`
need no account or bucket.

### Without the wrapper

Plain `terraform` in a stack folder behaves the same for everything that
matters:

- **State:** every stack has a committed `backend.tf` with the bucket, its
  region and the stack's key, generated by `make backends` from
  `config/global.yml`. `terraform init` uses it as written and never asks, so
  state cannot land anywhere else without a reviewed change. After changing the
  bucket in `global.yml`, run `make backends`; the pre-commit hook refuses a
  commit where any `backend.tf` disagrees.
- **Account:** the stack reads its account from `config/` and refuses to plan
  with credentials for any other.
- **Profile:** the stack reads `~/.config/infra/<repository folder>.yml` itself,
  so your chosen profile is used without `bin/tf`.

What the wrapper adds is checking before Terraform starts (an empty account, a
missing bucket, a stale `backend.tf`) and refusing `destroy` and the state
commands. VPCs, subnets and Transit Gateways refuse replacement either way.

## Creating a stack

A stack is a folder under `live/` with a link to each file in `live/common/`, so
it reads its identity and its settings, and its own `.tf` files:

```bash
make stack STACK=us-east-1/development/network
```

That runs `bin/stack`, which creates the folder, writes its `backend.tf`, and links every file in
`live/common/` (`../../../common/`: every stack is three levels deep, including
`global/shared/<component>`). It accepts `<region>/<environment>/<component>` or
`global/<environment>/<component>`. When `templates/<component>/` exists, it also writes a
`main.tf` that calls the template with the stack's region, and its environment
when the template takes one (a hub does not: it belongs to its region), and an
`outputs.tf` that passes on everything the template outputs. Without a template
the stack starts empty, for its own resources. It refuses a folder that is
already a stack.
