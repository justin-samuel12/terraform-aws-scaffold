# Day one

Everything needed to go from a fresh clone to a first set of environments,
in order, and what this scaffold leaves for you to add.

## 1. Outside this repository

Made by whoever owns the AWS Organization, before anything here runs:

- [ ] **An AWS account per environment**, plus one for the shared network
      (`shared`), with service control policies that allow what is built here
      ([configuration](configuration.md#before-anything-runs)).
- [ ] **Organization-wide security services**: CloudTrail, AWS Config,
      GuardDuty and Security Hub, run from the management or security account.
      Not built here ([global](global.md#organization-wide-services)).
- [ ] **IAM Identity Center** permission sets for the people who plan and
      apply. People never get IAM users or roles from this repository.
- [ ] **Domains**: which public domains you hold and where they are
      registered, so the `dns` stack can host their zones.

## 2. Fill in `config/`

- [ ] `config/global.yml`: `state.bucket` and `state.region`.
- [ ] `config/global.yml`: `sites`, one block per network reached over a VPN
      (its VPN address, BGP ASN, ranges, and the domains its DNS servers
      answer under `forward`); a site with no `ip_address` has no VPN yet.
- [ ] `config/global.yml`: `dns.private_zones`, `prefix_lists`.
- [ ] `config/<region>.yml`, for each region: `zones`, the hub's
      `account_id`, `team`, `cidr` and ASN, and each environment's
      `account_id`, `team`, `cidr`, `segment` and `public`. With one account
      for everything, leave those `account_id`s empty and set `account_id`
      once in `config/global.yml`. The ranges given
      are examples; choose ranges that overlap nothing you will connect to
      ([network](network.md#ip-plan)).
- [ ] Remove or add regions and environments to match yours. `make diagram`
      shows the result.
- [ ] Tags your organization requires, in `live/common/providers.tf`.

Then, on each machine that plans: `make setup` (profiles and prerequisites)
and `make hooks`.

Then the state bucket, once the shared account exists: `make bootstrap` creates
it, or checks and uses one that already exists
([configuration](configuration.md#the-state-bucket-make-bootstrap)).

## 3. Create the stacks

`make setup` creates every stack `config/` calls for, empty or from `examples/`.
To add one by hand, `make stack STACK=<region>/<environment>/<component>` calls
the matching template and writes `backend.tf`. `make order` lists what exists
and what is still missing. What every environment has:

- [ ] Each region's `shared`: `hub`, `logging`,
      `session-manager`, `documents`, `ecr` as needed.
- [ ] Each environment, in each region it runs in: `network`,
      `security-groups`, `endpoints`, `keys`, `backups`, then whichever of
      `load-balancers`, `certificates`, `waf`, `databases`, `storage`,
      `buckets`, `messaging`, `access`, `patching`, `compute`, `containers`, `kubernetes`, `records` and
      `lambda` it uses.
- [ ] With an account per environment: each environment account's own
      `global/<environment>/baseline`, `global/<environment>/iam`,
      `<region>/<environment>/logging` and
      `<region>/<environment>/session-manager`
      ([architecture](architecture.md#one-account-or-one-per-environment)).
- [ ] Delete example stacks you will not use.

## 4. Apply, in this order

Plans are read-only; applies are made by a person, one stack at a time,
reviewing each plan. A stack that looks something up fails its plan, naming
what is missing, until the stack that builds it has been applied.
`make order STACK=<region>/<environment>` works the order out from the
templates, in waves, and shows what is already applied
([architecture](architecture.md#apply-order)). By hand, one safe order is:

1. `global/shared/baseline`
2. Each region's `shared/hub`, the primary region last: it requests and accepts
   the peering with the others
3. Each region's `shared/logging`, then `global/shared/dns`, which creates the
   private zones and associates every hub with them
4. `global/shared/iam`
5. Each region's `shared/session-manager` and `shared/documents`
6. Per environment and region: `network`, `security-groups`, `endpoints`,
   `keys`, `backups`
7. `certificates`, then `load-balancers`, then `waf`
8. `buckets`, then `databases`, `storage`, `messaging`
9. `patching`, `access`
10. `compute`, `containers` and `kubernetes`, then `records`
11. `ecr`, `lambda`, `global/shared/cloudfront` as needed

## 5. What each environment needs written

The files are the environment's own: nothing is built until they exist.

- [ ] Security groups, one file each, before anything that uses them.
- [ ] IAM roles for every server and function, with their shared policies.
- [ ] Certificates for every HTTPS name.
- [ ] Load balancers, their listeners, and their own rules (priorities 1–999).
- [ ] Every group of servers in `compute` (listener rule priorities from 1000),
      each with a pinned image ID.
- [ ] Databases, file systems and buckets.
- [ ] Queues and topics, and the policies that let servers and functions use them.
- [ ] Patching windows, production later than staging.

## 6. Not included: add before you need it

| Item | Why it is not here | What to add |
|---|---|---|
| CI pipeline | depends on your CI system | the stages in [configuration](configuration.md#checking-without-credentials): `make check CHANGED=1` with `.terraform.d/` cached on every pull request, a plan of every changed stack, the full `make check` on main; applies stay manual |
| Deployment role for applications | depends on how applications ship | a role written as a file in an `iam` stack, trusting the GitHub OIDC provider the `pipeline` stacks create, for uploading CodeDeploy revisions and starting deployments; under `/deployed/` with its boundary like every other |
| CodeDeploy revisions | one bucket per environment, your naming | a `buckets/config/revisions.yml` file, and a shared `read-revisions` policy for deployed groups' roles ([compute](compute.md#deploying-with-codedeploy)) |
| Machine images | images are pinned by ID; building them is a pipeline of its own | EC2 Image Builder, or Packer, producing images with the SSM and CodeDeploy agents |
| Monitoring and alerting | depends on where alerts go | an alerts topic per environment in `messaging` (with `cloudwatch` as a publisher), and alarms for instance status, load balancer 5xx and unhealthy hosts, database CPU and storage, VPN tunnels, and failed backups |
| Budgets | per organization | AWS Budgets with alerts per account |
| Secrets | values never pass through Terraform | Secrets Manager secrets created empty, or with write-only values, for applications to read |
| Network inspection | not every network needs it | AWS Network Firewall in the hub's egress VPC ([network](network.md)) |
| Traffic mirroring | depends on your monitoring vendor | VPC Traffic Mirroring sessions to its collectors |
| Reverse DNS zones | depend on your ranges | private zones for `in-addr.arpa` of each VPC |
| Code owners | names your teams | `.github/CODEOWNERS`: `/config/` the network team, `/live/*/production/` production's owners |
| Public tiers | a decision per environment | `public: true` in `config/<region>.yml` for an environment that needs internet-facing load balancers or a VPN server |
