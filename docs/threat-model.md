# Threat model

Three boundaries carry most of the risk: the pipeline that turns a commit into AWS
changes, the hub every network passes through, and the line between accounts.
For each, what an attacker or a mistake could do, what stops it, where that is in
the repository, and how far it is proven.

**Status** says how far a control is proven today:

- **Tested** means enforced in code, and a test in this repository fails if it
  stops being true. Those tests run offline, against a mocked AWS or a model of
  IAM.
- **GitHub** means it is enforced by a GitHub setting. `bin/github` writes the
  setting and `bin/github verify` checks it, but no file can prove the setting is
  on.
- **Live** means it is designed in, but only a test in a real account can show it
  holds.
- **Open** means it is not mitigated yet.

## GitHub Actions and deployment

Assets: the apply roles, the state (which holds secrets), stored plans (likewise),
the protected branch.

| Threat | What stops it | Where | Status |
|---|---|---|---|
| A pull request's code runs with AWS credentials: a malicious provider, `data "external"`, `file()` of the token, a provider `endpoints` block, a provisioner | Code from a pull request never runs with credentials. `checks.yml` has no token; `plan.yml` runs `master`'s workflow and code, and takes only regular `.yml` files on allowed paths | `bin/ci classify`, `overlay`; `plan.yml`; `tests/ci/run.sh` | Tested; the event's behavior is GitHub |
| A configuration file in a pull request reads state or exfiltrates through the plan | YAML is decoded as data by `master`'s templates; reports name addresses and argument names, never values; errors have values removed; the plan role has no write access | `bin/ci changes_of`, `scrub` | Tested |
| A pull request's own workflow, or one on another branch, assumes any role | Every role trusts one workflow file at `@refs/heads/<branch>`, and AWS compares the whole subject | `deployment-policies` `subjects`; `bin/github` | Tested, GitHub |
| A pull request from a fork gets any AWS token | Jobs skip forks; GitHub gives forks no OIDC token by default; fork runs need approval | `plan.yml`, `checks.yml`; `bin/github` | GitHub |
| A workflow on `master` applies without approval | The apply job runs in the stack's GitHub environment, which waits for its reviewers | `apply.yml`; `bin/github` environments | GitHub |
| The person who proposed a plan approves and applies it | *Prevent self-review* on every environment; `bin/ci` also refuses the proposer for production and shared | `bin/github`; `bin/ci apply`; `tests/ci/run.sh` | GitHub, Tested |
| A merged change edits a workflow to skip approval | CODEOWNERS on `.github/`; the ruleset requires code owners' review and approval after the last push; the environment, not the workflow, holds the reviewers; the role's trust names the environment | `CODEOWNERS`, `bin/github` | GitHub |
| A different plan is applied than the one reviewed | Applied only by SHA-256 digest of the stored file; the stored record names the stack, commit and proposer; Terraform rejects a plan made before the state changed | `bin/ci propose`, `bin/ci apply`; `tests/ci/run.sh` | Tested |
| An approved digest is replayed, applied twice at once, or used against another stack, account, region or environment | A conditional write claims each digest once; Terraform refuses a stale plan; the record must name the stack, account, region, environment and duty, and the credentials the account; expiry; the commit must be on `master` | `bin/ci apply`; `ClaimAPlanOnce`; `tests/ci/run.sh` | Tested; the conditional write is AWS's, Live |
| Someone starts an authorized run with a digest nobody meant to apply | It must be a proposal from `apply.yml` on `master` for that stack, shown to the reviewer before approval; approval is per run and read back from GitHub's API | `bin/ci describe`, `approvers_of` | Tested, GitHub |
| Someone rewrites a stored plan or its record | Only the propose role can write `plans/`, and IAM refuses a write that is not a new object; the apply role only reads and deletes; the digest would no longer match; the record's own contents are protected by IAM and bucket versioning | `only_new_objects`; `requests.yml` `a_proposal_overwrites_a_record` | Tested |
| Plan contents leak through comments, logs or summaries | Reports list addresses, actions and changed argument names, never values; plans are never artifacts | `bin/ci changes_of`; `tests/ci/run.sh` "never shows a value" | Tested |
| An apply role widens its own permissions or trust | No pipeline role may change any `terraform-*` role, policy or the OIDC provider | `deployment-policies` `protect`; `requests.yml` `workload_changes_*` | Tested |
| An apply role escapes through a new role: creates one with admin, passes it to a server or function, which then edits an administrator role | New roles must be under `/deployed/` with the duty's boundary; only those can be passed; administrator policies cannot be attached; the boundary refuses every IAM change, assuming or passing anything outside `/deployed/`, the state, the trail and other environments | `deployment-policies` `RolesWithTheBoundary`, `NoIamChanges`, `AssumeOnlyDeployedRoles`; `make lint`; `requests.yml` `a_deployed_role_*` | Tested |
| A role's trust is widened to an outside account | IAM has no condition on a trust policy's contents, so IAM cannot refuse it. Roles written as files may be trusted only by services and this account (`templates/iam`, tested); fixed modules name their services; IAM Access Analyzer, from the baseline, reports outside access; an organization resource control policy can refuse it outright | `templates/iam` `outside`; `templates/baseline` | AWS limitation for code changes, which are reviewed |
| A workload runs code as another duty's role | Roles can be passed only under `/deployed/`, and only this duty's or the `iam` stack's | `PassOnlyThisDutysRolesAndTheIamStacks` | Tested |
| An apply role reads or rewrites state it does not own, or turns off versioning | Each duty's role reaches only its own stacks' keys; bucket settings and old versions are refused to every pipeline role | `deployment-policies` `OwnState`, `protect_state`; `requests.yml` `workload_*state*` | Tested |
| A compromised runner keeps credentials | No keys anywhere; tokens last an hour; runners are ephemeral | `bin/ci credentials`; [runners](ci-cd.md#runners) | Live |
| A malicious action or tool runs next to credentials | Actions pinned to commit SHAs, GitHub's own only; tool images pinned by digest; Dependabot proposes updates | workflows, `Makefile`, `bin/workflows` | Tested (by actionlint and review) |

## Hub and spoke

Assets: the boundary between production and everything else, the sites behind
the VPN, the shared services.

| Threat | What stops it | Where | Status |
|---|---|---|---|
| A spoke joins another segment's route table, or announces itself into production's | The spoke's network role has no Transit Gateway permission; its hub role may associate only with its own segment's table and announce only to its own segments, by the table's `Segment` tag | `deployment-policies` `network_statements`; `requests.yml` `the_hub_role_*` | Tested |
| A spoke's role moves or announces another environment's attachment | The hub role acts only on attachments tagged with its own environment, and cannot retag another's | Same; `the_hub_role_announces_production`, `the_hub_role_claims_production` | Tested |
| A newly requested attachment is accepted and tagged by the wrong environment's role in the window before its own accepts it | IAM cannot prevent it: `AcceptTransitGatewayVpcAttachment` offers only `ec2:Region`, the attachment's ID and tags, and an attachment from another account has no tags here yet. The code doing so is reviewed and approved per environment, and `bin/ci hub-audit`, nightly with drift, fails on any attachment whose owner account is not its environment's | `AcceptAttachmentsNotYetClaimed`; `bin/ci hub-audit` | AWS limitation, detected after the fact |
| An attachment's ownership tag is changed to move it | The hub role may tag an attachment only with its own environment, and cannot remove ownership tags | `requests.yml` `the_hub_role_retags_*`, `the_hub_role_removes_*` | Tested |
| An association or announcement drifts from `config/` | `bin/ci hub-audit` compares every attachment's owner, segment and announcements with `config/` | `tests/ci/run.sh` | Tested; live state is Live |
| A route added in a hub table opens a path between environments | Routes are the hub's alone; no spoke or workload role can create one; `restricted` and `standard` blackhole the internal range, so only propagated routes reach | `templates/hub`; `deployment-policies` `central_network` | Tested (offline), Live (forwarding) |
| Traffic passes between production and staging through `shared` | `shared` is reachable from both, but neither propagates into the other's table; return traffic follows the same tables | [routing](network.md#routing) | Live: only Reachability Analyzer or a test in an account shows the forwarding |
| A spoke authorizes its VPC on another environment's private zone | Route 53 has no tag conditions and the hub role is built before zones exist, so it reaches every zone in the hub's account; it can only add associations, never remove one | `AuthorizeAndAssociateItsPrivateZones` | AWS limitation; with own accounts, environments' zones are in their own accounts |
| A workload changes a VPC's routes, NACLs or gateways | The workload role is refused those actions, and resources tagged `network` | `deployment-policies` `spoke_network`; `workload_changes_the_vpc_routes`, `workload_deletes_the_vpc` | Tested |
| Peering between hubs leaks a segment into another region | Each table's peering routes list only the segments it may reach | `templates/hub` `reach`; hub tests | Tested (offline), Live |
| A VPN site announces a route that overrides an environment's | Sites associate with `shared`, propagate to every table; a more specific route from a site would win | `templates/hub` VPN | Open: no prefix filter on what a site announces |
| A parent organization's gateway routes traffic in ways this repository cannot see | With `owner: parent`, routing is theirs; nothing here claims to isolate it | [accounts](accounts.md#a-parent-organizations-network) | Not ours to mitigate |

## Accounts

Assets: each account's resources, the hub's account, the state bucket's account.

| Threat | What stops it | Where | Status |
|---|---|---|---|
| A stack applies to the wrong account | Each provider is pinned to its account; a stack's identity is in `stack.tf` and checked against its folder; it deploys only to a configured region and environment | `live/common/providers.tf`; wiring tests | Tested |
| Staging's roles change production in a shared account | Tag-based limits on both environment and duty; production must have its own account unless `config/` accepts otherwise | `deployment-policies` `apply_environment`, `apply_ownership`; `templates/pipeline` `dedicated_accounts` | Tested, with the limits in [accounts](accounts.md#sharing-an-account) |
| A cross-account role is assumed by more than intended | `terraform-network-<environment>` trusts one role by ARN; `dns-<environment>` its account, limited to its own names | `deployment-policies` `network_trust`; `templates/dns` | Tested |
| A pipeline role reaches the organization | Refused in every pipeline role and boundary | `protect` | Tested |
| Ownership tags are removed or a resource is moved by retagging | Removal is refused by tag key; a tag naming another environment or duty is refused; servers can only be tagged as they are created | `tag_ownership`; `requests.yml` `workload_retags_*`, `workload_removes_*` | Tested; untagged non-server resources can still be claimed (AWS limitation) |
| A resource policy widens access around a boundary | Explicit denies in the boundary still apply; `s3:PutBucketPolicy`, `kms:PutKeyPolicy` and `secretsmanager:PutResourcePolicy` on another environment's resources are refused by tag or name, and on its own stay within reviewed code | `boundary`, `apply_environment` | Tested for names and tags |
| Delegated administration in the Organization is misused | Not built here; no pipeline role can change the organization | | Outside this repository |
| A compromised account's admin reads another account's state | The bucket policy limits each account to its own prefixes; the state is encrypted with S3-managed keys, so S3 access alone reads it | `bootstrap/main.tf` | Open: a customer managed key would add an independent check |
| Someone uses a person's admin access instead of the pipeline | Not prevented: people apply the pipeline stacks and break glass. CloudTrail records it | [break-glass](operations.md#break-glass-access) | Organizational |

SCPs are not assumed. Where the Organization can add them, these repeat the most
important limits outside every account's own IAM: refuse leaving the
Organization, stopping CloudTrail, changing the state bucket's policy except by a
named break-glass role, and every region `config/` does not name.
