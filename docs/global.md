# Shared and global stacks

What every environment uses, placed by its real scope in AWS: account-wide
under `live/global/shared/`, regional under `live/<region>/shared/`, and owned
by one environment under that environment. Much of what is often treated as
global is regional in AWS (certificates, ECR, S3, Lambda, WAF for load
balancers), so it is not global here.

Each stack below is built from our own module and a template that reads the
`.yml` files beside it. With no files, or empty ones, a stack builds nothing.

## Order

`baseline` first, then each region's `hub` and `logging`, then the global `dns`
(its private zones are created with the primary hub's VPC, and every other hub
is associated with them), then the rest. A stack that looks something up (a log
bucket, a zone, a load balancer) fails its plan, naming what is missing, until
the stack that builds it has been applied. `make order` works the order out
([architecture](architecture.md#apply-order)).

## Account-wide: `live/global/shared/`

Global stacks run in the primary region (the hub with `primary: true`).

### `baseline`

No settings: the same for every account. For every region in `config/`:

- S3 public access blocked for the whole account, whatever a bucket says;
- EBS encryption on by default, and public sharing of EBS snapshots blocked;
- an IAM Access Analyzer, reporting anything shared outside the account.

A region added to `config/` is covered on the next plan.

### `iam`

Workload roles, one file per role. Never people: they sign in through your
organization's IAM Identity Center.

```yaml
# live/global/shared/iam/grafana.yml
description: Grafana servers
services:
  - ec2
managed_policies:
  - AmazonSSMManagedInstanceCore
policies:
  - read-tags
```

Permissions several roles share are customer-managed policies, one file each in
`policies/`, named by the roles that use them:

```yaml
# live/global/shared/iam/policies/read-tags.yml
description: Read instance tags, for service discovery
statement:
  - actions:
      - ec2:DescribeInstances
      - ec2:DescribeTags
    resources:
      - '*'
```

A role can still carry a `statement` list of its own for what only it needs,
written as in `aws_iam_policy_document`: `effect`, `actions`, `resources`, and
`condition` (each with `test`, `variable` and `values`).

Every role EC2 assumes also gets the built-in `session-manager` policy: decrypt
with the sessions key (`alias/shared-sessions`, or `alias/<environment>-sessions`
in an environment's own account, and no other key) and write to
the `/ssm/sessions` log groups, which every server needs for Session Manager,
whatever its role is for.

Only the listed services may assume a role. AWS managed policies are named
under `managed_policies`, ours under `policies`; neither is copied. A role EC2 assumes gets an instance profile of the same name, which
compute finds by name. The plan refuses a role without a description or a
service, a role naming a policy that is not in `policies/`, a policy without a
description or statements, and any statement, in a role or a policy, that
allows every action on every resource.

### `dns`

Public hosted zones from `zones.yml` beside the stack, and the private hosted
zones listed in `config/global.yml` (`dns.private_zones`), which belong to the
network team because every VPC attaches to them.

```yaml
# live/global/shared/dns/zones.yml
public:
  - example.com
```

Zones are never destroyed by a plan: a public zone holds records that exist
nowhere else. A private zone is created with the primary hub's VPC, and this
stack associates every other region's hub with it, so no hub has to wait for
`dns` and the primary hub can still be applied last. Every network attaches its
own VPC from its own stack, and the zone ignores its VPC list afterwards so
this stack never undoes that. Hubs must all be in the primary hub's account for
private zones; the plan refuses one that is not.

### `cloudfront`

One file per distribution.

```yaml
# live/global/shared/cloudfront/media-assets.yml
aliases:
  - assets.example.com
origin_bucket: example-media-assets
certificate: assets.example.com
waf: true
```

The bucket stays private: an origin access control signs every request, and
the stack's output gives the exact statement the bucket's policy needs. Viewers
are sent to HTTPS, TLS 1.2 or later, with AWS's managed caching and
security-headers policies. CloudFront's certificates and WAF exist only in
us-east-1, so this stack has a second provider for that region (`us-east-1.tf`)
and finds the certificate there by its domain. `waf: true` gives the
distribution its own CLOUDFRONT web ACL, which logs to a WAF log bucket in
us-east-1 (`aws-waf-logs-<account>-us-east-1`), so that region needs a logging
stack before any distribution uses WAF.

## Regional, shared by every environment: `live/<region>/shared/`

### `hub`

Built: Transit Gateway, egress, VPN, resolver endpoints, prefix lists
([network](network.md)).

### `logging`

Two buckets per region, named by account and region so every stack can find
them without reading this one's state: `lb-logs-<account>-<region>` for load
balancer access logs, and `aws-waf-logs-<account>-<region>` for WAF. Encrypted,
versioned, private (no ACLs), refusing anything not over TLS, with the exact
delivery permissions each service needs, and retention from `logging.yml`
(default 365 days). Never destroyed by a plan.

### `ecr`

```yaml
# live/us-east-2/shared/ecr/ecr.yml
repositories:
  - gitops
keep_images: 30
untagged_days: 14
```

Tags are immutable, so a deployed tag always means the same image; every push
is scanned; untagged images expire, and only the newest tagged ones are kept.
Every repository is copied to every other region in `config/`.

## Owned by one environment: `live/<region>/<environment>/`

### `certificates`

```yaml
# live/us-east-2/operations/certificates/certificates.yml
grafana:
  domain_name: grafana.example.com
  subject_alternative_names:
    - metrics.example.com
  zone: example.com
```

Validated through DNS in the named public zone, so they renew by themselves.
The plan refuses a name that is not in its zone. Load balancers find
certificates by domain.

### `waf`

One file per web ACL, for the environment's public load balancers.

```yaml
# live/us-east-2/production/waf/web.yml
rate_limit: 2000
load_balancers:
  - web
```

AWS's common, known-bad-inputs and IP-reputation rule groups by default, a rate
limit per IP, every request logged to the region's WAF log bucket without the
`Authorization` header, and attached to the named load balancers.

### `lambda` (operations)

One file per function, with its code beside it in `src/<name>/`. Before
writing one, check whether AWS already does the job (below).

```yaml
# live/us-east-2/operations/lambda/report.yml   (code in src/report/)
runtime: python3.12
handler: app.handler
memory_size: 256
timeout: 30
schedule_expression: rate(1 day)
environment:
  variables:
    LEVEL: info
statement:
  - actions:
      - s3:GetObject
    resources:
      - arn:aws:s3:::example-reports/*
```

Each function gets its own role, allowed only to write its own log group plus
the statements in its file, and its own log group kept 365 days. Functions run
on Graviton (arm64) with JSON logs. The code is zipped with fixed file modes, so
a different umask on another machine is not a code change. A `schedule_expression` runs it
through EventBridge, which alone may invoke it. An `event_source_mapping`
takes messages from a queue instead, and `sns_topic_subscription` subscribes the
function to topics ([messaging](messaging.md#sending-and-reading)). The plan refuses an environment
variable whose name looks like a secret (password, token, key, credential): the
AWS provider prints environment variables in plans, so a function reads its
secrets from SSM or Secrets Manager when it runs. It also refuses a file without
`runtime` and `handler`, a function with no code in `src/<name>/`, and any
statement allowing every action on every resource.

## Functions AWS already provides

Many functions that end up in an account do something AWS offers itself:

| Function that | Use instead |
|---|---|
| Creates, copies or deletes AMIs and snapshots on a schedule | AWS Backup plans: schedules, retention and cross-region copies |
| Posts root logins or changes to chat | EventBridge rules to SNS or AWS Chatbot |
| Restarts unhealthy instances | EC2 automatic recovery and Systems Manager |
| Scales build runners | an Auto Scaling group |

## Organization-wide services

**CloudTrail, AWS Config, GuardDuty and Security Hub** are best run once for
the whole AWS Organization, from its management or security account. They are
not built here; if your organization does not run them, add them before
anything else ([day one](day-one.md)).
