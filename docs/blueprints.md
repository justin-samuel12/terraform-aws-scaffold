# Blueprints

A blueprint is the one definition of a kind of app: everything every backend
service (say) has in common, written once and reviewed once. An app on it is a
few lines in each environment's stack: which blueprint, and the few things that
make it itself.

```yaml
# live/us-east-2/production/compute/config/accounts-service.yml
blueprint: backend-service/v1
count: 2
instance_type: t3.large
listener_rule:
  listener_arn: services/443
  priority: 1200
  condition:
    path_pattern:
      values:
        - /accounts-service/*
```

```yaml
# live/us-west-2/staging/compute/config/apps/accounts-service.yml
blueprint: backend-service/v1
count: 2
listener_rule:
  listener_arn: services/443
  priority: 1200
  condition:
    path_pattern:
      values:
        - /accounts-service/*
```

Three stacks take blueprints: compute, containers and databases. Each reads
only its own folder, which mirrors `live/`, so a database file cannot name a
compute blueprint, and the same name could exist in two stacks without a clash:

```
blueprints/
  compute/        backend-service, frontend, staff-app, container-app
  containers/     ecs-service
  databases/      sqlserver, aurora-postgres
```

A file names its blueprint without the stack, `blueprint: sqlserver/v1`
(`blueprints/databases/sqlserver/v1.yml`): the stack is already known from
where the file sits.

Blueprints are optional at every level. A file without `blueprint:` is an
ordinary hand-written one, exactly as before, and the two sit side by side in
one stack. Staging can use a blueprint while production keeps a hand-written
file. Nothing uses a blueprint until a file names it.

## The blueprints

### compute

| Blueprint | For | Load balancer | Reached by | Its servers' group | The app's file must give |
|---|---|---|---|---|---|
| `backend-service/v1` | internal APIs that other apps call | `services` (internal) | `path_pattern`, `/<app>/*` | `backend-services`, plus the shared three | `listener_rule` |
| `frontend/v1` | web apps and APIs on the internet, third parties' sites included | `public` | `host_header` | `frontends`, plus the shared three | `listener_rule` |
| `staff-app/v1` | web apps for people inside | `staff` (internal) | `host_header` | `staff-apps`, plus the shared three | `listener_rule` |
| `container-app/v1` | Docker on its own servers | `staff` (internal) | `host_header` | `container-apps`, plus the shared three | `listener_rule` |

The load balancers are the environment's `<environment>-services`,
`-public` and `-staff`, made by its load-balancers stack, and the groups come
from its security-groups stack: a blueprint names them, so every environment
that uses it needs them. The shared three are on every compute app:
`services-lb-clients` and `sqlserver-clients`, empty groups that let it call the
services load balancer and SQL Server ([security groups](security-groups.md#designing-groups)),
and `monitoring-agent`. With its own group that makes four of the five a server
may have, so an app can add one group of its own. The servers always sit in the `private` tier, even a
frontend's; only the public load balancer is in the `public` tier, and only
its group may reach them, on 443.

A container app is tagged `isContainerized: true`, so CodeDeploy shares one
application across the environments and each deploys through its own group,
`primary-<environment>` ([compute](compute.md#deploying-with-codedeploy)). Its
role can also pull images from ECR, and its disk is larger for them.

```yaml
# live/us-east-2/production/compute/config/sso.yml
blueprint: frontend/v1
count: 2
listener_rule:
  listener_arn: public/443
  priority: 1100
  condition:
    host_header:
      values:
        - sso.example.com
```

### containers

| Blueprint | For | Load balancer | Reached by | Its tasks' group | The app's file must give |
|---|---|---|---|---|---|
| `ecs-service/v1` | HTTP APIs on ECS Fargate | `services` (internal) | `path_pattern`, `/<app>/*` | `ecs-services`, `services-lb-clients`, `sqlserver-clients` | `container_definitions`, `listener_rule` |

Every service's container listens on 8080 (`portMappings` with
`containerPort: 8080`), which is what the `ecs-services` group admits from the
services load balancer. Each runs in the private subnets, is deployed by
CodeDeploy (`deployment_controller.type: CODE_DEPLOY`) with a 10% canary,
starts at `cpu: 512`, `memory: 1024` and `desired_count: 2`, and scales on CPU
between two and six. An app may change `cpu`, `memory` (a pair Fargate
accepts), `desired_count`, its scaling range and its health check, and may list
its own `network_configuration.security_groups`, which are added to the
blueprint's `ecs-services` ([containers](containers.md)).

```yaml
# live/us-east-2/production/containers/config/payments-api.yml
blueprint: ecs-service/v1
container_definitions:
  - name: payments-api
    image: 111111111111.dkr.ecr.us-east-2.amazonaws.com/payments-api:3.1.0
    portMappings:
      - containerPort: 8080
listener_rule:
  listener_arn: services/443
  priority: 1400
  condition:
    path_pattern:
      values:
        - /payments-api/*
cpu: 1024
memory: 2048
```

### databases

| Blueprint | For | Instance classes | The database's file must give |
|---|---|---|---|
| `sqlserver/v1` | SQL Server Standard 2022: Multi-AZ, TDE, native backups through the `<environment>-sqlserver-backups` role, Eastern time | `db.m6i` and `db.r6i`, large to 2xlarge | `vpc_security_group_ids` |
| `aurora-postgres/v1` | Aurora PostgreSQL 16: a writer and a reader, on Graviton by default | `db.r7g` or `db.r7i`, large to 4xlarge | `vpc_security_group_ids` |

Who may connect is decided per database, so each names its own group. A
database may change its instance class and storage (SQL Server) or class and
number of instances (Aurora); its engine, version, Multi-AZ, options and
encryption are the blueprint's ([data](data.md)).

```yaml
# live/us-east-2/production/databases/config/billing.yml
blueprint: sqlserver/v1
instance_class: db.m6i.xlarge
allocated_storage: 200
vpc_security_group_ids:
  - billing-database
```

## What a blueprint holds

```yaml
# blueprints/compute/backend-service/v1.yml
description: An internal HTTP service behind a load balancer, reached by path
allows:
  - count
  - instance_type
  - ami
  - target_group.health_check
  - target_group.stickiness
  - members.*.tags
adds:
  - vpc_security_group_ids
requires:
  - listener_rule
instance_types:
  default: t3a.small
  allowed:
    - t3a.small
    - t3a.medium
    - t3a.large
environments:
  production:
    instance_types:
      default: m7i.large
      allowed:
        - m7i.large
        - m7i.xlarge
        - m7i.2xlarge
role:
  managed_policy_arns:
    - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    - arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
    - session-manager
    - read-revisions
group:
  count: 1
  ami: ami-0123456789abcdef0
  tier: private
  vpc_security_group_ids:
    - backend-services
  user_data: scripts/ubuntu.sh
  target_group:
    port: 443
    protocol: HTTPS
    health_check:
      path: /{app}/status
      matcher: "200"
  listener_rule:
    port: 443
  tags:
    Backup: standard
    DNS: "{server}"
    CodeDeploy: "['{app}']"
```

`description`, `allows`, `requires` and the rest of a blueprint's top level are
the blueprint's own keys, read by the blueprint module; a top-level key it does
not know is refused. The settings every app gets sit under one key named for
what the stack builds: `group` (compute), `service` (containers) or `database`
(databases). Inside it are exactly the keys of a hand-written file in that
stack, which are the provider's arguments: the blueprint writes nothing a file
could not.

| Key | Means |
|---|---|
| `allows` | the keys, or paths into maps (`target_group.health_check`, `members.*.tags` for any one server), an app's file may set |
| `requires` | the keys an app's file must set |
| `instance_types` (compute), `instance_classes` (databases) | `allowed`: the only instance types or classes an app may choose; `default`: the one it gets if its file names none. The choice is never also written in the body |
| `environments` | an environment's own `instance_types` or `instance_classes`, replacing the blueprint's there and nowhere else |
| `adds` | lists an app adds to rather than replaces, by key or `parent.key`: `vpc_security_group_ids` in compute, `network_configuration.security_groups` in containers, so an app's own groups join the blueprint's |
| `role` (compute) | an IAM role and instance profile the blueprint creates for every app on it, below |

`{app}` is the file's name, `{environment}` and `{region}` the stack's. The
listener rule is the app's own, written out with Terraform's keys for an
`aws_lb_listener_rule`: its `listener_arn` (`services/443`, the load balancer and
the listener's port), its `priority` (1000 and up, unique on that load balancer) and its `condition`, `host_header.values`
(full host names, `customer-staging.example.com`) and/or
`path_pattern.values` (`/accounts-service/*`), at most five together.
Any other required value, such as an image or a database's security groups, is
simply the file's own. The result
then goes through the stack like any hand-written file: in compute, placement,
target group, listener rule, DNS and CodeDeploy ([compute](compute.md)).

The boot script is shared, not a copy per blueprint: `scripts/ubuntu.sh` names
the host from its `Server` tag, installs every update and the troubleshooting
tools, and starts the CodeDeploy and CloudWatch agents if the image has them.
If the updates ask for a restart, the server restarts a minute later and the
agents start with it. If the updates fail, the boot carries on and the patch
window catches up, so a package mirror cannot leave a server unnamed.
`container-app/v1` boots from `scripts/ubuntu-container.sh`, the same script
with Docker added, and no other server starts Docker. Applications belong in
the image, and secrets in Vault; a hand-written group can name either script,
or another in `scripts/`.

## What an app may change, and how

- **Only what `allows` lists**, and an instance type or class only from the blueprint's `allowed`,
  or its environment's where it has one: the compute blueprints keep production
  off burstable T sizes this way, defaulting to `m7i.large`. A
  file that sets anything else is refused, naming what it may set: a standard
  app cannot drift from its blueprint by a key or two.
- **Maps merge two levels deep**: `target_group.health_check.path` changes the
  health check's path and keeps the rest of the target group the blueprint's.
  Lists, such as a condition's `values`, are replaced whole, which is why a
  blueprint allows a list only when an app owns all of it.
- **Required values** (`requires`) must be there: a listener rule's priority,
  load balancer and condition are each app's own, so each app writes its rule.

The three things apps most often need to change:

```yaml
# live/us-east-2/production/compute/config/accounts-service.yml
blueprint: backend-service/v1
listener_rule:
  listener_arn: services/443
  priority: 1200
  condition:
    path_pattern:
      values:
        - /accounts-service/*
        - /accountss/*
target_group:
  health_check:
    path: /accounts-service/health
vpc_security_group_ids:
  - accounts-files
```

The second path is an old one, kept during a rename; the health check's
matcher and protocol stay the blueprint's; and the app's servers are in
`backend-services` and `accounts-files`.

- **Health checks** merge: name only what differs.
- **Paths and host names** are written in the rule, every one, nothing filled
  in: the plan refuses two apps claiming the same host or path on a load
  balancer, a short host name, and a path not starting with `/`.
- **Security groups** are added, never replaced, so no app can drop the group
  its load balancer reaches it through. Every blueprint takes them. A server or
  task has at most five, which the plan checks.
- **Tags** merge: an app adds its own and may give one of the blueprint's
  another value (`WorkloadType`), except the platform's own
  ([below](#what-no-file-can-change)). `members.<server>.tags`
  sets one server's tag outright, winning over the group's. In a blueprint,
  `{server}` fills in each server's name (`DNS: "{server}"`); only a blueprint
  may use it, because a file writes its own values.

Tags, lowest first: the provider's defaults on every resource (`ManagedBy`,
`Environment`, `Component`, `Repository`, `Team`), the blueprint's, the file's,
then a server's own. The tags a stack sets itself (`Name`, `Server`, `Group`,
`PatchGroup`, `Subnet`; `Service` on ECS) always win, and a file that uses one
of those names is refused, since that is where patching and deployments look.
`Backup: standard` is an ordinary tag: every compute blueprint sets it, so its
servers are in the environment's AWS Backup plan, and an app could set it to
something else to leave the plan.

## A role of its own

A compute blueprint's `role` is the one place a blueprint creates something
its app's file does not mention. Every app on it gets an IAM role and an
instance profile, both named `<environment>-<app>-<region>`, trusted by EC2 and
set as the servers' `iam_instance_profile`, with exactly the blueprint's
permissions, in the same keys as the `iam` stack's roles: `managed_policy_arns`, an
AWS managed policy by its ARN or one of the account's shared policies (made by
the `iam` stack) by name; and `statement`, inline statements (`effect`,
`actions`, `resources`, `condition`, with `{app}`, `{environment}` and
`{region}` filled in). Any other key is refused. An app's file cannot set
`iam_instance_profile` itself. Every backend service can do the
same things, and each is still its own identity: Vault's AWS auth knows a
server by its role, so each app's Vault role binds to its own and no app can
read another's secrets. Roles are global, so the region is in the name. A
hand-written group keeps naming a role from the `iam` stack. ECS services get
a task role of their own from the containers stack, with or without a
blueprint.

## Versions

`backend-service/v1` in a compute file is the file
`blueprints/compute/backend-service/v1.yml`, and that file is a contract: once it
is released, it never changes, so an app on it never changes unless its own file
does. Each stack's blueprint folder has a `versions.yml` that lists every
released version, its status, and the SHA-256 of the file as it was released:

```yaml
# blueprints/compute/versions.yml, once a v2 has been released
backend-service/v1:
  status: deprecated
  sha256: 237cf08ecbd3e31d1fc5f1769e0a310f8bcb000bca3e7ca3dc6706f908e3ad44
  replaced_by: backend-service/v2
  note: v2 runs on m7i; set instance_type to keep t3a
backend-service/v2:
  status: current
  sha256: 9b1e...
```

Every plan of every stack on blueprints checks it, so a mistake is caught before
anything reaches AWS:

| You do | The plan says |
|---|---|
| Edit a released version | It changed after it was released, and to put the change in the next version, which it names |
| Use a version that is not in `versions.yml` | It is not released, with the exact line to add once it is reviewed |
| Use a `deprecated` version | It still works, unchanged, with a warning naming the version to move to and the note |
| Use a `retired` version | It is refused, naming the version to move to |
| Mark a version deprecated or retired without `replaced_by`, or replaced by one that is retired or missing | Refused |
| Delete the file of a version still listed | Refused |

`status` is `current`, `deprecated` or `retired`; `replaced_by` names a released
version; `note` says what changes for an app that moves. `.gitattributes` keeps
blueprint files in LF on every checkout, so the SHA-256 is the same on every
machine.

### Releasing a version

1. Copy the newest version to the next number, `v2.yml`, and change it.
2. Plan an app on it in staging: the plan refuses it as not released, and prints
   the line to add.
3. In the same pull request, add that line to `versions.yml` with
   `status: current`. The reviewers approve the version and its checksum together.

### Moving an app to a new version

Move one environment at a time, staging first:

1. Change the app's `blueprint:` line to the new version.
2. Read the version's `note`, and set in the app's file whatever it should keep
   from the old one, if the new version allows it.
3. Plan. The plan shows exactly what the move changes for that app; nothing else
   moves with it.
4. Once every app has moved, mark the old version `deprecated`, then `retired`
   when nothing names it. `make render` shows who is still on which version.

A deprecated version keeps working for as long as it is listed. Retiring one is
the only way a blueprint change can stop an app's plan, and it is a reviewed
change to `versions.yml`, not an edit to the blueprint.

### What no file can change

The tags the platform sets from where the stack is, `ManagedBy`, `Environment`,
`Component`, `Repository` and `Team`, cannot be set in a blueprint or an app's
file, under `tags` or a member's `tags`. The pipeline's permissions keep
environments and duties apart by those tags ([accounts](accounts.md)), so a file
that could set `Environment: production` in staging would be a way around them.

## Seeing it

```bash
make render                       # every app on a blueprint, in every stack, and where
make render APP=accounts-service   # one app, side by side across environments
```

```
accounts-service
                                  us-east-2/production/compute   us-west-2/staging/compute
  blueprint                       backend-service/v2             backend-service/v1
  count                           2                              2
  instance_type                   t3.large                       ·
  priority                        1200                           1200
  ! accounts-service is on more than one blueprint version
```

`·` is the blueprint's own value. The plan remains the final word on what
changes in AWS.

## How it is built

The `blueprint` module (`modules/blueprint`) does the work for all three
stacks and builds nothing: the stack's files and its blueprint folder go in,
and the expanded files, anything wrong with them, and warnings come out. Each
stack then treats the expanded files as its own and checks them as it checks any
file, and shows the warnings as a check. The module's tests cover each rule
above, and check that every released version of the real blueprints is intact;
each stack's tests plan apps on the real blueprints.

## When not to use one

An app that truly differs, such as a SQL Server cluster with chosen addresses,
or RDS Custom for one database's needs, stays a hand-written file. That is not
a failure of the blueprint: it makes the exception visible instead of hiding
it in a near-copy.
