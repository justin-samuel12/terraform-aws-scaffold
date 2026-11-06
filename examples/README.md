# Examples

A complete set of example files for every stack: what an environment looks like
when it is filled in. They are never planned or applied from here. To use one,
copy it into the matching stack under `live/` and change the names, sizes and
image IDs:

```bash
cp examples/us-east-1/development/databases/dashboards.yml live/us-east-2/operations/databases/
```

The folders mirror `live/`: `global/shared/` for account-wide stacks,
`us-east-1/shared/` for the region's shared stacks, and `us-east-1/development/`
for one environment. They are checked against their own small config,
`examples/config/` (one region, us-east-1, one environment, development), so
they do not depend on yours:

```bash
make check-examples      # every example, planned through its template against a mocked AWS
```

## How the files fit together

The example environment runs an internal dashboards application behind an
internal load balancer, deployed by CodeDeploy, with its database, file
system, buckets, DNS name and certificate; monitoring collectors behind a
network load balancer; build runners; a two-node SQL Server cluster with chosen
addresses; a tunnel to the database; export requests through a topic and a
queue to a Lambda function; a daily Lambda function; patching and backups;
and the same kind of app three ways: on servers (compute, with two backend
services on a blueprint), on ECS Fargate (containers: a rolling service and a
blue/green canary), and on EKS Auto Mode (kubernetes: the cluster, two app
identities, and sample manifests). Each file names the others by name, never by ID.

## Account-wide: `global/shared/`

| Stack | Files | Shows |
|---|---|---|
| `baseline` | none | no settings: the same for every account |
| `iam` | `config/role/dashboards.yml`, `config/role/runner.yml`, `config/role/collector.yml`, `config/instance-profile/*.yml`, `config/policy/session-manager.yml`, `config/policy/read-revisions.yml`, `config/policy/read-tags.yml`, `config/policy/domain-join.yml` | a role per kind of server with its trust written out, AWS managed and shared policies by ARN or name, an instance profile per role, a statement of a role's own |
| `cloudfront` | `config/distribution/assets.yml`, `config/web-acl/assets.yml` | a private bucket served through CloudFront, with its certificate and its own web ACL |

## The region's shared stacks: `us-east-1/shared/`

| Stack | Files | Shows |
|---|---|---|
| `hub` | none | built from `config/` alone |
| `logging` | `config/lb-logs.yml`, `config/aws-waf-logs.yml` | each log bucket's lifecycle rules |
| `ecr` | `config/dashboards.yml`, `config/runner.yml`, `config/replication-configuration/registry.yml` | repositories, their lifecycle and pull policies, replication |
| `session-manager` | `config/document/SSM-SessionManagerRunShell.yml`, `config/log-group/sessions.yml` | the preferences document and the session log group |
| `documents` | `config/install-cloudwatch-agent.yml` | an SSM Command document written as YAML |

## Off the hub: `us-east-1/adhoc/`

| Stack | Files | Shows |
|---|---|---|
| `network` | `config/peering/development.yml`, `config/route-table/public.yml`, `config/route-table/private.yml`, `config/route-table/data.yml`, `config/network-acl/data.yml` | an environment with `connectivity: peering`: its own internet and NAT gateways, a peering to development, every route written, and a network ACL on its data tier ([network](../docs/network.md#off-the-hub-connectivity-peering)) |

## One environment: `us-east-1/development/`

| Stack | Files | Shows |
|---|---|---|
| `network` | `config/route-table/private.yml`, `config/route-table/data.yml` | built from `config/`, with routes back to the ad hoc environment's peering |
| `security-groups` | `config/dashboards-lb.yml`, `config/dashboards.yml`, `config/database.yml`, `config/services-lb.yml`, `config/services-lb-clients.yml`, `config/sqlserver-clients.yml`, `config/operators.yml`, `config/monitoring-agent.yml`, `config/collector.yml`, `config/endpoints.yml`, `config/domain-member.yml` and more | a group per role, in the provider's own arguments: `referenced_security_group_id` by name, and empty client groups (`services-lb-clients`, `operators`) admitted in place of subnets; `cidr_ipv4` for the office; ports and ranges; egress written out, none on the databases |
| `endpoints` | `config/ssm.yml`, `config/s3.yml` and ten more | interface endpoints by subnet and group name; a gateway endpoint on named route tables |
| `keys` | none | two keys per environment, no settings |
| `backups` | `config/backup-vault/development.yml`, `config/backup-plan/development.yml` | a locked vault and the plan's rules |
| `certificates` | `config/dashboards.yml`, `config/services.yml` | DNS-validated certificates, one with an alternative name |
| `load-balancers` | `config/internal.yml`, `config/services.yml`, `config/collectors.yml` | internal application load balancers with their 404 and redirect written out, listener rules; a network load balancer with a target group |
| `waf` | `config/internal.yml` | a web ACL with its rules written out, on a load balancer |
| `databases` | `config/dashboards.yml`, `config/billing.yml`, `config/ledger.yml`, `config/jobs.yml`, `config/reporting.yml`, `config/salesforce-sync.yml` | PostgreSQL, SQL Server and Aurora, on blueprints and written in full |
| `storage` | `config/shared-files.yml` | EFS with a mount target per zone and an access point that creates its directory |
| `buckets` | `config/revisions.yml`, `config/exports.yml`, `config/sqlserver-backups.yml` | lifecycle rules written out; a backed-up bucket with object lock |
| `compute` | `config/dashboards.yml`, `config/api.yml`, `config/collector.yml`, `config/runner.yml`, `config/sqlserver.yml`, `config/accounts-service.yml`, `config/inventory-service.yml`, `config/deployments/external-api-service.yml` | the shapes of a group: a target group, listener rules, CodeDeploy and DNS records; an Auto Scaling group that tracks CPU; behind a network load balancer; plain; pinned with chosen addresses and a data disk; two backend services on a blueprint ([blueprints](../docs/blueprints.md)) |
| `containers` | `config/orders-api.yml`, `config/checkout.yml`, `config/payments-api.yml` | ECS on Fargate with container definitions written out: a rolling service scaling on CPU; a blue/green canary through CodeDeploy ([containers](../docs/containers.md)) |
| `kubernetes` | `config/cluster/development.yml`, `config/app/orders-api.yml`, `config/app/reports-worker.yml`, `manifests/` | EKS Auto Mode: the cluster, two app identities, and the Kubernetes files an app team writes, not applied by Terraform ([kubernetes](../docs/kubernetes.md)) |
| `records` | `config/runner.yml`, `config/sql.yml` | an A record to a server, a CNAME |
| `access` | `config/dashboards-db.yml` | a Session Manager tunnel to the database, written as a Session document |
| `domain-join` | `config/windows.yml` | Windows servers tagged `Domain` join the domain through Systems Manager, into one OU, with the environment's join account |
| `patching` | `config/maintenance-window/patching.yml`, `config/patch-baseline/*.yml` | the maintenance window and a baseline per operating system |
| `lambda` | `config/report.yml`, `config/exports.yml`, `config/src/<name>/app.py` | a scheduled function and a queue consumer, their permissions, log retention and code |
| `messaging` | `config/queue/exports.yml`, `config/queue/exports-dlq.yml`, `config/topic/exports.yml` | a queue with its dead-letter queue and delivery policy, a topic alarms publish to, its subscriptions |

What each key means is in the stack's own doc under [`docs/`](../docs).
