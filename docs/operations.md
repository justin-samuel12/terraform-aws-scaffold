# Operations

What to do when something goes wrong, and how to change ownership on purpose.
Terraform cannot undo an apply: there is no rollback, only a new plan toward the
state you want. Every procedure here ends in a reviewed plan, and none of them
deletes state or infrastructure without one.

`bin/tf`, which `make` uses, refuses `destroy`, `state rm`, `state mv`,
`state push`, `force-unlock` and `-destroy`. Those are done deliberately, by a
person, with `terraform` itself and the profile of the stack's account, as below.
Prefer the blocks Terraform plans and reviews (`moved`, `import`, `removed`) to
any command that writes state directly.

In the commands, `S` is the stack (`us-west-2/staging/compute`), `P` the AWS
profile `config` maps to its environment, and `B` the state bucket in
`config/global.yml`, and `K` the stack's state, the `key` in its `backend.tf`
(`us-west-2/staging/compute/terraform.tfstate`). Its lock is `K.tflock`, next to
it.

## A failed apply

An apply that stops leaves everything it finished in place and in the state;
what failed is neither built nor recorded.

1. Read the error. Most are a missing permission, a quota, a name in use, or
   something another stack has not built yet.
2. Fix the cause in code or in AWS.
3. `make plan STACK=S`. The plan shows only what is left to do; review it as any
   other.
4. `make apply STACK=S`. A saved plan is never reused after a failure; Terraform
   refuses it, since the state changed.

From the pipeline it is the same: propose again, approve the new digest, apply.
The failed run's claim on its digest stays in `applied/`, with its result beside
it, so that plan can never be applied again.

## A partial apply

Same as a failed apply, with one more check: a resource that AWS created but
Terraform did not record (the error arrived after the create) shows in the next
plan as one to create, and its create then fails with a name already in use.
Import it rather than delete it:

```hcl
import {
  to = module.compute.aws_instance.servers["app01"]
  id = "i-0123456789abcdef0"
}
```

Add the block to the stack in a pull request, plan, apply, then remove the block.

## A plan is refused as already claimed

The digest was claimed by an earlier run, successful or not, in
`applied/<stack>/<digest>.json`. Nothing is wrong: propose again and approve the
new digest. The claim is the audit record, so leave it.

## A stuck state lock

A lock is an object next to the state. It is left behind when a run is killed.

1. Make sure nothing is running on that stack: no pipeline run (the Apply
   workflow's runs, and Plan and Drift take no lock), and no one at a terminal.
2. Read who holds it: the error names the lock's ID, who and when.
3. Release it:

   ```bash
   AWS_PROFILE=P terraform -chdir=live/S force-unlock <lock id>
   ```

   Expected: `Terraform state has been successfully unlocked!`
4. Plan the stack; it should show only what the interrupted run did not finish.

## Recovering state

The bucket keeps every version of every state file, and no pipeline role can
delete an old version.

1. List the versions:

   ```bash
   aws s3api list-object-versions --profile P --bucket B --prefix K \
     --query 'Versions[].[VersionId,LastModified,Size]' --output table
   ```

2. Download the one before the damage, and read it:

   ```bash
   aws s3api get-object --profile P --bucket B --key K --version-id <id> old.tfstate
   terraform show -json old.tfstate | jq '.values.root_module'
   ```

3. Restore it by copying that version over the current one, so the history keeps
   both:

   ```bash
   aws s3api copy-object --profile P --bucket B --key K \
     --copy-source "B/K?versionId=<id>"
   ```

4. Plan. What changed in AWS since that version shows as drift; decide resource
   by resource whether to import, change code, or let the plan put it back.

Never restore a state older than a resource it would forget: that resource would
then show as one to create, and its create would fail.

## Moving state

Within a stack (a renamed resource, a module wrapped around it), write a `moved`
block and plan: the plan shows a move, not a destroy and create.

```hcl
moved {
  from = aws_s3_bucket.logs
  to   = module.buckets.aws_s3_bucket.buckets["logs"]
}
```

Between stacks (a resource that another stack should own):

1. In the new stack, add an `import` block for it, and the resource itself.
2. In the old stack, replace the resource with a `removed` block, so Terraform
   forgets it without destroying it:

   ```hcl
   removed {
     from = aws_security_group.groups["shared-tools"]
     lifecycle {
       destroy = false
     }
   }
   ```

3. Plan both in one pull request. Apply the old stack first (it forgets), then
   the new (it adopts). Both plans should change nothing in AWS.

A whole stack to a new folder: move the folder, `make backends`, and review the
new `stack.tf` and `backend.tf`. The stack now points at a new, empty key; copy
the old state to it with `aws s3 cp` between the two keys, then plan: it should
show no changes. Delete the old key only after a clean plan.

## The wrong account

A stack cannot plan against the wrong account: its provider is pinned
(`allowed_account_ids`), and the plan stops with the account it expected. If it
does stop:

1. `aws sts get-caller-identity --profile P`: which account the profile reaches.
2. Fix the profile in your machine config, or `account_id` in `config/` if that
   is what is wrong.
3. If a resource was built in the wrong account before the pin existed, import it
   into a stack of that account, or remove it there with a reviewed plan.

## Importing, and changing who owns a resource

Something built by hand becomes Terraform's with an `import` block and a
resource that matches it, planned until the plan shows no change. Something
Terraform should stop managing goes with a `removed` block and `destroy = false`.
Either way, the plan is the review: it must show the intended import or
forgetting and nothing else.

## Upgrading a blueprint

See [moving an app to a new version](blueprints.md#moving-an-app-to-a-new-version).
The version an app names never changes under it, so an upgrade is always one
app's file, one environment at a time.

## Upgrading the provider

1. Change the constraint in `live/common/versions.tf` (and modules' and
   templates' `versions.tf`), then `make backends`.
2. Update each stack's lock file:

   ```bash
   for s in $(bin/order --offline | grep -oE '[a-z0-9-]+/[a-z0-9-]+/[a-z0-9-]+' | awk '!seen[$0]++'); do
     terraform -chdir=live/$s init -backend=false -upgrade >/dev/null && echo "upgraded $s"
   done
   ```

3. `make check`. Read the provider's changelog for each resource type whose
   tests changed.
4. Plan every stack in one environment. A provider upgrade should show no
   changes; any it does show are reviewed one by one before an apply.
5. If the new version breaks a plan, put back the old constraint and lock files:
   nothing was applied.

## A failed Transit Gateway attachment

| What you see | Usually | Do |
|---|---|---|
| The attachment stays `pendingAcceptance` | The hub's side did not run: the network stack's `aws.hub` profile, or `terraform-network-<environment>` is missing | Apply `global/shared/pipeline`, check `profiles.shared`, plan the network stack again |
| `InvalidTransitGatewayID.NotFound` | The account has not accepted the hub's RAM share, or the Organization's sharing is off | Plan the network stack: it accepts the share. With `organization_sharing: true`, check RAM's setting in the management account |
| `AccessDenied` on `AssociateTransitGatewayRouteTable` | The route table's `Segment` is not the environment's `segment` | Fix `segment` in `config/<region>.yml`; never widen the role |
| The attachment is `failed` | Its subnets: one per zone, in the `transit` tier | Plan the network stack; the attachment is replaced |

A parent organization's gateway: acceptance and route tables are theirs. Give
them the attachment's ID from `make output STACK=S`.

## A routing mistake

1. Find the path: in the hub's account, `aws ec2 search-transit-gateway-routes
   --transit-gateway-route-table-id <table> --filters Name=type,Values=static,propagated`
   for each table the source is associated with, and the VPC route tables on both
   ends.
2. Confirm with VPC Reachability Analyzer between the two ENIs. It reads the
   configuration and sends no traffic.
3. Fix it in code: a segment in `config/`, a route-table file, or a hub template
   change. Plan the hub and the affected networks together, and look in the plan
   for every route that changes in every table.
4. After the apply, run the same analysis again, and check the other direction:
   return traffic follows the destination's tables.

`bin/ci hub-audit <file>`, read-only, compares every attachment on the hubs with
`config/`: its owner account, its segment, its announcements. It runs nightly
with drift. It shows configuration; it does not show that a packet arrives, which
only Reachability Analyzer or a test in an account can.

## Cross-account access fails

| Error | Check |
|---|---|
| `AccessDenied` assuming `terraform-network-<environment>` or `dns-<environment>` | The calling role's ARN against the trust policy (`aws iam get-role`), and that the caller's policy allows `sts:AssumeRole` on it |
| `AccessDenied` on the state bucket | The bucket policy has the account's prefixes: run `make bootstrap` again after adding an account |
| An apply role refused an action it needs | `aws iam simulate-principal-policy --policy-source-arn <role arn> --action-names <action> --resource-arns <arn>`, with `--context-entries` for the resource's tags. A missing action is added to the duty in `templates/duties.yml`, reviewed, and the pipeline stack applied by a person |
| A deployed role refused | Its boundary: the same simulation with `--permissions-boundary-policy-input-list` |

## Break-glass access

The pipeline is never the only way in. People with administrator access through
IAM Identity Center (or the organization's access role) can always plan and
apply with `make`, and are the only ones who apply the `pipeline` stacks and the
state bucket.

When the pipeline is broken or a fix cannot wait:

1. Say so where the team will see it, with the stack and why.
2. Plan and apply with `make`, from a commit on `master`, reviewed afterwards if
   not before.
3. Open a pull request with anything that changed, so code and AWS agree again.
4. Review the CloudTrail events for that session.

Never fix a pipeline role's permissions from the pipeline. A person changes
`templates/duties.yml`, reviews the plan of the `pipeline` stack, and applies it.

## Disaster recovery

| Lost | Recover from | How |
|---|---|---|
| A state file | Its earlier versions | [Recovering state](#recovering-state) |
| The state bucket | Nothing in AWS; keep it from being lost: versioning, no delete by any pipeline role, and replication to another region if the organization requires it | Recreate it with `make bootstrap`, then `import` each stack's resources: slow, so prevent it |
| A region | The other region's hub and environments | Build the region's stacks again from `config/`; data comes back from backups and replicas (see [data](data.md)) |
| A hub's Transit Gateway | Code | Apply the hub, then every network in the region; attachments are replaced |
| An account | Code and backups | A new account in `config/`, then [adding an account](accounts.md#adding-an-account), then each stack in order |

Infrastructure is code, so most of it is rebuilt by applying it again. Data is
not: databases, buckets and file systems come back only from backups and
replicas, and how is in each one's documentation.

## Checking the permissions in a test account

The offline tests model IAM; only AWS can confirm it. In an account made for it,
with nothing else in it:

1. Put the account in a copy of `config/` as one environment's, apply that
   environment's `pipeline` stack as a person.
2. `bin/iam-check --aws`: Access Analyzer and the policy simulator against every
   request in `modules/deployment-policies/tests/requests.yml`, and compare with
   what the offline run decided.
3. Assume `terraform-apply-<environment>-workload` and try, expecting
   `AccessDenied`: creating a role without the boundary; changing a
   `terraform-*` role; changing a resource tagged with another environment.
4. Apply one small stack of each duty through the pipeline, then destroy them,
   as a person, with a reviewed plan. Include a security group rule that names a
   shared prefix list, and a server launched into a subnet: those are where a
   duty uses a resource another owns, and the tag limits are most likely to
   refuse something a stack needs.
