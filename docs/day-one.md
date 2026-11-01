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

`make setup` asks for all of this and writes it, showing every change first.
The same keys can be edited by hand:


- [ ] `config/global.yml`: `state.bucket` and `state.region`.
- [ ] `config/global.yml`: `hq` (your office or data centre's VPN address,
      BGP ASN and ranges), or leave `ip_address` empty and no VPN is built.
- [ ] `config/global.yml`: `dns.forward` (domains to send to your own DNS
      servers), `dns.private_zones`, `prefix_lists`.
- [ ] `config/<region>.yml`, for each region: `zones`, the hub's
      `account_id`, `team`, `cidr` and ASN, and each environment's
      `account_id`, `team`, `cidr`, `segment` and `public`. The ranges given
      are examples; choose ranges that overlap nothing you will connect to
      ([network](network.md#ip-plan)).
- [ ] Remove or add regions and environments to match yours. `make diagram`
      shows the result.
- [ ] Tags your organization requires, in `live/common/providers.tf`.

Then, on each machine that plans: `make setup` (profiles and prerequisites)
and `make hooks`. Before any account exists, `make check` already plans every
stack's files against a mocked AWS.

Once, for the whole repository: `make bootstrap` creates the state bucket in
the shared account, moves its own state into it, and writes every stack's
`backend.tf` ([configuration](configuration.md#the-state-bucket-make-bootstrap)).
Commit what it changes.

## 3. Create the stacks

The example has one region (`us-east-1`), its `shared` stacks, the global
stacks, and one environment, `development`, with every stack and example files
in each. Rename or copy it for your environments, and create anything else with
`make stack STACK=<region>/<environment>/<component>`, which calls the matching
template and writes `backend.tf`:

- [ ] Replace the example files with your own; `make check-files` checks them.
- [ ] Each additional region's `shared`: `hub`, `logging`, `session-manager`,
      `documents`, `ecr` as needed.
- [ ] Each environment, in each region it runs in: `network`,
      `security-groups`, `endpoints`, `keys`, `backups`, then whichever of
      `load-balancers`, `certificates`, `waf`, `databases`, `storage`,
      `buckets`, `access`, `patching`, `compute`, `apps`, `records` and
      `lambda` it uses.
- [ ] Delete example stacks and files you will not use.

## 4. Apply, in this order

Plans are read-only; applies are made by a person, one stack at a time,
reviewing each plan. A stack that looks something up fails its plan, naming
what is missing, until the stack that builds it has been applied.

1. `global/shared/baseline`
2. Each region's `shared/hub`, the primary region first (it requests the
   peering)
3. Each region's `shared/logging`, then `global/shared/dns`
4. `global/shared/iam`
5. Each region's `shared/session-manager` and `shared/documents`
   (import `SSM-SessionManagerRunShell` first if the account already has it:
   [systems manager](systems-manager.md#session-manager))
6. Per environment and region: `network`, `security-groups`, `endpoints`,
   `keys`, `backups`
7. `certificates`, then `load-balancers`, then `waf`
8. `databases`, `storage`, `buckets`
9. `patching`, `access`
10. `compute` and `apps`, then `records`
11. `ecr`, `lambda`, `global/shared/cloudfront` as needed

## 5. What each environment needs written

The files are the environment's own: nothing is built until they exist.

- [ ] Security groups, one file each, before anything that uses them.
- [ ] IAM roles for every server and function, with their shared policies.
- [ ] Certificates for every HTTPS name.
- [ ] Load balancers, their listeners, and their own rules (priorities 1–999).
- [ ] Applications in `apps` (routes from 1000), other servers in `compute`,
      each with a pinned image ID.
- [ ] Databases, file systems and buckets.
- [ ] Patching windows, production later than staging.

## 6. Not included: add before you need it

| Item | Why it is not here | What to add |
|---|---|---|
| CI pipeline | depends on your CI system | a pipeline that runs `make fmt-check lint test` and plans every changed stack on a pull request; applies stay manual |
| CI role | depends on your CI system | an IAM role trusting your CI's OIDC provider, for plans, and for uploading CodeDeploy revisions and starting deployments |
| CodeDeploy revisions | one bucket per environment, your naming | a `buckets/revisions.yml` file, and a shared `read-revisions` policy for deployed applications' roles ([compute](compute.md#apps-one-file-per-application)) |
| Machine images | images are pinned by ID; building them is a pipeline of its own | EC2 Image Builder, or Packer, producing images with the SSM and CodeDeploy agents |
| Auto Scaling groups | servers here are fixed members | a template for groups that scale (build runners, workers) |
| Monitoring and alerting | depends on where alerts go | an SNS topic per environment, and alarms for instance status, load balancer 5xx and unhealthy hosts, database CPU and storage, VPN tunnels, and failed backups |
| Budgets | per organization | AWS Budgets with alerts per account |
| Secrets | values never pass through Terraform | Secrets Manager secrets created empty, or with write-only values, for applications to read |
| Network inspection | not every network needs it | AWS Network Firewall in the hub's egress VPC ([network](network.md)) |
| Traffic mirroring | depends on your monitoring vendor | VPC Traffic Mirroring sessions to its collectors |
| Reverse DNS zones | depend on your ranges | private zones for `in-addr.arpa` of each VPC |
| Code owners | names your teams | `.github/CODEOWNERS`: `/config/` the network team, `/live/*/production/` production's owners |
| Public tiers | a decision per environment | `public: true` in `config/<region>.yml` for an environment that needs internet-facing load balancers or a VPN server |
