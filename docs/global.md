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

Workload roles, policies and instance profiles, one file each, in
`config/role/`, `config/policy/` and `config/instance-profile/`. Never people:
they sign in through your organization's IAM Identity Center. The keys are the
arguments of `aws_iam_role`, `aws_iam_policy` and `aws_iam_instance_profile`,
and the file name is the resource's name.

```yaml
# live/global/shared/iam/config/role/grafana.yml
description: Grafana servers
assume_role_policy:
  statement:
    - effect: Allow
      actions:
        - sts:AssumeRole
      principals:
        - type: Service
          identifiers:
            - ec2.amazonaws.com
managed_policy_arns:
  - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  - session-manager
  - read-tags
```

```yaml
# live/global/shared/iam/config/instance-profile/grafana.yml
role: grafana
```

```yaml
# live/global/shared/iam/config/policy/read-tags.yml
description: Read instance tags, for service discovery
statement:
  - actions:
      - ec2:DescribeInstances
      - ec2:DescribeTags
    resources:
      - '*'
```

`assume_role_policy` is the role's trust, written out: only the principals it
names may assume it. `managed_policy_arns` lists the policies attached to the role
(`aws_iam_role_policy_attachment`): an ARN as written, AWS's managed policies
included, or the name of a policy in `config/policy/`. A role's own `statement`
list, for what only it needs, becomes its inline policy (`aws_iam_role_policy`),
named `<role>-policy`. Every statement is written as in
`aws_iam_policy_document`: `effect` (Allow when left out), `actions`,
`resources` (`principals` in a trust policy), and `condition`, each with
`test`, `variable` and `values`.

Nothing is added to a role that its files do not say. A server's role needs
`session-manager`, a policy file like any other
(`examples/global/shared/iam/config/policy/session-manager.yml`): decrypt with
the sessions key (`alias/*-sessions`, and no other key) and write to the
`/ssm/sessions` log groups, which every server needs for Session Manager. A
role EC2 uses needs an instance profile file naming it; compute finds the
profile by its name.

The plan refuses a file outside the three folders, a key that is not one of
these arguments, two files with one name, a role or policy without a
description, a role without `assume_role_policy`, a policy without statements,
a `managed_policy_arns` entry that is neither an ARN nor a policy here, an instance
profile for a role that is not here, and any statement, in a role or a policy,
that allows every action on every resource.

### `dns`

Every zone in the hub, all from `config/global.yml`: one public zone per domain
in `dns.public_domain`, and the private ones, the private domain itself and
anything in `dns.private_zones`. Every VPC attaches to the private ones, so
they belong to the network team. The stack has no files of its own.

Zones are never destroyed by a plan: a public zone holds records that exist
nowhere else. A private zone is created with the primary hub's VPC, and this
stack associates every other region's hub with it, so no hub has to wait for
`dns` and the primary hub can still be applied last. Every network attaches its
own VPC from its own stack, and the zone ignores its VPC list afterwards so
this stack never undoes that. Hubs must all be in the primary hub's account for
private zones; the plan refuses one that is not.

### DNS: public domains, one private domain

`config/global.yml` lists the public domains and names one private domain:

```yaml
dns:
  inbound: true
  public_domain:
    - example.com
    - otherbrand.com
  private_domain: example.internal
  resolve_all_private:
    - operations
```

`public_domain` lists the zones where apps people open are reached, each one
in the hub. Nothing is ever written there by default: a public name is written
in full, `my-staging.example.com`, and a DNS record goes in a public zone
only when its file names that zone. `private_domain` is one name: a zone in the
hub for names every environment shares, with each environment's own zone under
it (`.internal`, never `.local`, which laptops resolve by multicast). An
environment's own private zone is its default: a record that names no zone goes
there. `resolve_all_private` lists the environments whose VPCs resolve every
environment's private names, through the hub: the command center.

```
example.com              public    the hub's: my-staging.example.com, my.example.com, …
otherbrand.com                  public    the hub's: app-staging.otherbrand.com, …
example.internal               private   the hub's, attached to every VPC: names they all share
staging.example.internal       private   staging's own account, attached to its VPCs and the hubs
production.example.internal    private   production's own account, the same
operations.example.internal    private   operations' own account, the same
```

The environments' zones are not delegated from `example.internal`: private
zones cannot delegate. They overlap instead. A VPC asks the most specific zone
attached to it, so a staging server finds `db.staging.example.internal` in its
own zone and `ldap.example.internal` in the hub's, and gets nothing for
`db.production.example.internal`, which no zone attached to it holds.

- **Apps people open** have public names, staff apps included: a staff app's
  name resolves to its internal load balancer's private address, reachable only
  through the hub, so a free public certificate covers it. Every name is
  written in full in a listener rule's `condition.host_header.values`
  (`my-staging.example.com`), and its DNS record is a file of its own in the environment's records
  stack, naming the zone. Names are the environments' to keep
  apart: the environment goes in the name.
- **Machines** have private names, in `<environment>.example.internal`, seen
  from the environment's own VPCs and the hubs. A server's `DNS` tag is its
  name there, written by its compute stack without asking
  (`survey01.staging.example.internal`); a record with no `zone` goes there too,
  written with the environment's own account. A record in the hub's
  `example.internal` names it, like a public one.
- **Certificates are files,** one per certificate in the certificates stack's
  `config/`, each naming its domain and the public zone it is validated in;
  none is made without being asked for. Load balancers pick the one that
  matches each app.

### `zones` (one per environment: `live/global/<environment>/zones`)

The environment's private zone, attached to its VPC in every region it has one
and to every region's hub VPC, never destroyed by a plan. Attached to the hubs,
it is answered by the hub's inbound resolver (`dns.inbound`), so people on the
VPN and in the office resolve `sso01.staging.example.internal`. Across
accounts the zone's owner authorizes each hub VPC and the hub attaches it, as
the network stack does for the hub's own private zones.

The environments in `resolve_all_private` see every environment's private
names: the hub forwards the private domain (`example.internal`) to its own
inbound resolver, shares that rule, and only those environments' network
stacks attach it. A forwarding rule wins over a private zone of the same name,
so their questions about `example.internal` go to the hub, which has every
environment's zone attached; their own zone, more specific, still answers
first. Every other environment resolves only its own private names and the
hub's.

### Who may write in the public domain

The `dns` stack gives each environment in another account than the domain's a
role, `dns-<environment>`, which only that environment's account can take, and
which may change names in the public domains and nothing else.

Stacks that write public names (`compute`, `records`, `certificates`) do it
through the `aws.dns` provider, which takes that role across accounts and is the
environment's own credentials in one account. The rest of the hub's work
(attachments, routes, private zones) stays on `aws.hub`.

### `cloudfront`

One file per distribution in the stack's `config/distribution/`, and one per
web ACL in `config/web-acl/`. A distribution file is `aws_cloudfront_distribution`'s
own arguments; a web ACL file is the same as in the `waf` stack below, built
with scope `CLOUDFRONT` in us-east-1 and named `cloudfront-<file>`.

```yaml
# live/global/shared/cloudfront/config/distribution/media-assets.yml
aliases:
  - assets.example.com
origin:
  - origin_id: example-media-assets
    domain_name: example-media-assets
default_cache_behavior:
  target_origin_id: example-media-assets
  viewer_protocol_policy: redirect-to-https
  allowed_methods:
    - GET
    - HEAD
    - OPTIONS
  cached_methods:
    - GET
    - HEAD
  compress: true
  cache_policy_id: Managed-CachingOptimized
  response_headers_policy_id: Managed-SecurityHeadersPolicy
price_class: PriceClass_100
viewer_certificate:
  acm_certificate_arn: assets.example.com
  ssl_support_method: sni-only
  minimum_protocol_version: TLSv1.2_2021
web_acl_id: media-assets
```

| Key | Meaning |
|---|---|
| `aliases` | The domains it answers on |
| `origin` | A list of `origin_id` and `domain_name`: the bucket's name, which the stack turns into its regional domain (a domain ending `.amazonaws.com` passes through) |
| `default_cache_behavior` | `target_origin_id`, `viewer_protocol_policy` (`redirect-to-https` or `https-only`), `allowed_methods`, `cached_methods`, `compress`, `cache_policy_id` and optionally `response_headers_policy_id`; a policy is named (`Managed-CachingOptimized`) or given by its ID |
| `price_class` | Required: `PriceClass_100`, `PriceClass_200` or `PriceClass_All` |
| `viewer_certificate` | `acm_certificate_arn` (the domain of an issued certificate in us-east-1, or its ARN) with `ssl_support_method` and a `minimum_protocol_version` of TLS 1.2 or later; or `cloudfront_default_certificate: true` for a distribution without aliases |
| `web_acl_id` | A web ACL in `config/web-acl/`, by file name, or a web ACL's ARN |

Built in: every origin is reached through the distribution's origin access
control, so the bucket stays private, and the stack's output gives the exact
statement the bucket's policy needs; IPv4 and IPv6, HTTP/2 and HTTP/3, no geo
restriction. CloudFront's certificates and WAF exist only in us-east-1, so this
stack has a second provider for that region. Its web ACLs log to the WAF log
bucket in us-east-1 (`aws-waf-logs-<account>-us-east-1`), so that region needs
a logging stack before a distribution names a web ACL. The plan refuses an
unknown key, a missing `price_class`, a file outside the two folders, a
`web_acl_id` that is not a file in `config/web-acl/`, plain HTTP for viewers,
and TLS below 1.2.

## Regional, shared by every environment: `live/<region>/shared/`

### `hub`

Built: Transit Gateway, egress, a VPN per site link, resolver endpoints, prefix lists, and (in the primary hub, when enabled) the AWS Managed Microsoft AD
([network](network.md)).

### `logging`

Two buckets per region, one file each in `config/`: `lb-logs.yml` and
`aws-waf-logs.yml`, named `<file>-<account>-<region>` so every stack can find
them without reading this one's state. A file takes `tags` and
`lifecycle_configuration.rule` (`id`, `status`, `filter.prefix`,
`expiration.days`, `noncurrent_version_expiration.noncurrent_days`,
`abort_incomplete_multipart_upload.days_after_initiation`); without rules
nothing expires. Fixed: encrypted, versioned, private (no ACLs), TLS only, the
delivery permissions the bucket's service needs, never destroyed by a plan.

### `ecr`

```yaml
# live/us-east-2/shared/ecr/config/gitops.yml
lifecycle_policy:
  policy:
    rules:
      - rulePriority: 1
        description: Untagged images expire after 14 days
        selection:
          tagStatus: untagged
          countType: sinceImagePushed
          countUnit: days
          countNumber: 14
        action:
          type: expire
      - rulePriority: 2
        description: Keep the newest 30 images
        selection:
          tagStatus: any
          countType: imageCountMoreThan
          countNumber: 30
        action:
          type: expire
```

One file per repository: `tags`, `lifecycle_policy.policy` and
`repository_policy.policy`, each the policy document written as YAML. In a
statement's `Principal.AWS`, an environment's name (or `shared`) stands for its
account. Fixed: immutable tags, scan on push, encryption. Replication is
`config/replication-configuration/registry.yml`, the registry's
`aws_ecr_replication_configuration` (`registry_id: shared` is this account). No
files, nothing built.

## Owned by one environment: `live/<region>/<environment>/`

### `certificates`

```yaml
# live/us-east-2/operations/certificates/config/grafana.yml
domain_name: grafana.example.com
subject_alternative_names:
  - metrics.example.com
validation_method: DNS
key_algorithm: RSA_2048
route53_record:
  zone_id: example.com
```

One file per certificate, named after it, in `aws_acm_certificate`'s own
arguments: `domain_name`, `subject_alternative_names`, `validation_method`
(`DNS`, the only method that renews by itself), `key_algorithm` (`RSA_2048`,
`EC_prime256v1` and the other ACM algorithms) and `tags`, all written. 
`route53_record` is the resource that proves the certificate: its `zone_id` is the
public hosted zone, by name, that the DNS validation records go in, through the
hub's account. The plan refuses any other key and a name that is not in that
zone. Load balancers find
certificates by domain.

### `waf`

One file per web ACL, for the environment's public load balancers, in the
stack's `config/` folder. A file is `aws_wafv2_web_acl`'s own arguments, named
`<environment>-<file>`; nothing is filled in.

```yaml
# live/us-east-2/production/waf/config/web.yml
default_action:
  allow:
rule:
  - name: rate-limit
    priority: 0
    action:
      block:
    statement:
      rate_based_statement:
        limit: 2000
        aggregate_key_type: IP
    visibility_config:
      cloudwatch_metrics_enabled: true
      metric_name: production-web-rate-limit
      sampled_requests_enabled: true
  - name: AWSManagedRulesCommonRuleSet
    priority: 1
    override_action:
      none:
    statement:
      managed_rule_group_statement:
        name: AWSManagedRulesCommonRuleSet
        vendor_name: AWS
    visibility_config:
      cloudwatch_metrics_enabled: true
      metric_name: production-web-AWSManagedRulesCommonRuleSet
      sampled_requests_enabled: true
visibility_config:
  cloudwatch_metrics_enabled: true
  metric_name: production-web
  sampled_requests_enabled: true
resource_arns:
  - web
```

| Key | Meaning |
|---|---|
| `default_action` | `allow:` or `block:` (an empty block, as in HCL) |
| `rule` | A list of rules: `name`, `priority`, `statement` (`managed_rule_group_statement` with `name` and `vendor_name`, or `rate_based_statement` with `limit`, at least 100 per five minutes, and `aggregate_key_type`), `visibility_config`, and `override_action` (`none:` or `count:`) for a managed rule group or `action` (`allow:`, `block:` or `count:`) for any other |
| `visibility_config` | `cloudwatch_metrics_enabled`, `metric_name`, `sampled_requests_enabled`: all three, on the web ACL and on every rule |
| `resource_arns` | The load balancers it protects: a file name from the environment's load-balancers stack, or an ARN |

Built in: every request is logged to the region's WAF log bucket without the
`Authorization` or `Cookie` header. The plan refuses an unknown key (naming
the arguments the resource takes), a rule without its name, priority, statement
or visibility_config, two rules sharing a name or priority, and a managed rule
group with `action` instead of `override_action`.

### `lambda` (operations)

One file per function in `config/`, with its code in `config/src/<name>/`.
Before writing one, check whether AWS already does the job (below).

```yaml
# live/us-east-2/operations/lambda/config/report.yml   (code in config/src/report/)
runtime: python3.12
handler: app.handler
memory_size: 256
timeout: 30
cloudwatch_event_rule:
  schedule_expression: rate(1 day)
cloudwatch_log_group:
  retention_in_days: 365
environment:
  variables:
    LEVEL: info
statement:
  - effect: Allow
    actions:
      - s3:GetObject
    resources:
      - arn:aws:s3:::example-reports/*
```

`runtime`, `handler`, `memory_size`, `timeout` and `environment` are
`aws_lambda_function`'s; left out, `memory_size` and `timeout` are the
provider's (128 MB, 3 seconds). `cloudwatch_log_group.retention_in_days` is
required: how long the function's own log group keeps its logs, 365 unless
there is a reason for another period. `cloudwatch_event_rule.schedule_expression`
runs the function on an EventBridge schedule, which alone may invoke it.
`event_source_mapping` takes messages from a queue and `sns_topic_subscription`
subscribes the function to topics, each by the queue's or topic's name in this
environment or its ARN ([messaging](messaging.md#sending-and-reading)).
`statement` is the function role's own permissions, written as in
`aws_iam_policy_document`: `effect`, `actions`, `resources` and `condition`.

Each function gets its own role, allowed to write its own log group plus the
statements in its file (and, with `event_source_mapping`, to read its queue).
Functions run on Graviton (arm64) with JSON logs. The code is zipped with fixed
file modes, so a different umask on another machine is not a code change. The
plan refuses a key that is not one of these, two files with one name, an
environment variable whose name looks like a secret (password, token, key,
credential: the AWS provider prints environment variables in plans, so a
function reads its secrets from SSM or Secrets Manager when it runs), a file
without `runtime`, `handler` or `cloudwatch_log_group.retention_in_days`, a
function with no code in `config/src/<name>/`, and any statement allowing every
action on every resource.

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
