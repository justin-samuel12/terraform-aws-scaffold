# Blueprints

A blueprint is the one definition of a kind of app: everything every backend
service (say) has in common, written once and reviewed once. An app on it is a
few lines in each environment's compute stack: which blueprint, and the few
things that make it itself.

```yaml
# live/us-east-2/production/compute/accounts-service.yml
blueprint: backend-service/v1        # = blueprints/backend-service/v1.yml
priority: 1200
count: 2
instance_type: t3.large
```

```yaml
# live/us-west-2/staging/compute/accounts-service.yml
blueprint: backend-service/v1
priority: 1200
count: 2
```

Blueprints are optional at every level. A compute file without `blueprint:`
is an ordinary hand-written group, exactly as before, and the two sit side by
side in one stack. Staging can use a blueprint while production keeps a
hand-written file. Nothing uses a blueprint until a file names it.

## What a blueprint holds

```yaml
# blueprints/backend-service/v1.yml
description: An internal HTTP service behind a load balancer, reached by path
allows:            # what an app's file may set; everything else is fixed
  - count
  - instance_type
  - ami
  - target_group.health_check
  - target_group.stickiness
  - tags.Owner
requires:          # what an app's file must set
  - priority
instance_types:    # the sizes an app may choose from
  - t3.small
  - t3.large
role:              # the permissions each app on it gets, in a role of its own
  managed_policies: [AmazonSSMManagedInstanceCore, CloudWatchAgentServerPolicy]
  policies: [session-manager, read-revisions]
group:             # a compute group, as in any compute file
  count: 1
  instance_type: t3.small
  tier: private
  security_groups: [backend-services]
  user_data: boot.sh        # beside the blueprint
  target_group:
    port: 443
    protocol: HTTPS
    health_check: { path: /{app}/status, matcher: "200" }
  listener_rules:
    - load_balancer: internal
      path_pattern: [/{app}/*]
      priority: "{priority}"
  tags:
    CodeDeploy: "['{app}']"
```

`{app}` is the file's name, `{environment}` and `{region}` the stack's, and
`{priority}` (or any other required key) the file's own value. The group then
goes through the compute stack like any hand-written one: placement, target
group, listener rule, DNS, CodeDeploy ([compute](compute.md)).

## What an app may change, and how

- **Only what `allows` lists**, and a size only from `instance_types`. A file
  that sets anything else is refused, naming what it may set: a standard app
  cannot drift from its blueprint by a key or two.
- **Maps merge two levels deep**: `target_group.health_check.path` changes the
  health check's path and keeps the rest of the target group the blueprint's.
  Lists, such as `listener_rules`, are replaced whole.
- **Required values** (`requires`) must be there: a listener rule's priority is
  unique on its load balancer, so each app gives its own.

## A role of its own

Every app on a blueprint with a `role` gets an IAM role and instance profile
made for it, `<environment>-<app>-<region>`, with exactly the blueprint's
permissions: AWS managed policies by name, the account's shared policies (made
by the `iam` stack) by name. Every backend service can do the same things, and
each is still its own identity: Vault's AWS auth knows a server by its role, so
each app's Vault role binds to its own and no app can read another's secrets.
Roles are global, so the region is in the name. A hand-written group keeps
naming a role from the `iam` stack.

## Versions

`backend-service/v1` is the file `blueprints/backend-service/v1.yml`. A change
to what every backend service gets is a new file, `v2.yml`, and apps move to it
one environment at a time, staging first, by changing one line. A blueprint in
use is never edited in place: that would change every app at once, in every
environment, on its next plan.

## Seeing it

```bash
make render                       # every app on a blueprint, and where
make render APP=accounts-service   # one app, side by side across environments
```

```
accounts-service
                                  us-east-2/production   us-west-2/staging
  blueprint                       backend-service/v2     backend-service/v1
  count                           2                      2
  instance_type                   t3.large               ·
  priority                        1200                   1200
  ! accounts-service is on more than one blueprint version
```

`·` is the blueprint's own value. The plan remains the final word on what
changes in AWS.

## When not to use one

An app that truly differs, such as a SQL Server cluster with chosen addresses,
stays a hand-written compute file. That is not a failure of the blueprint: it
makes the exception visible instead of hiding it in a near-copy.
