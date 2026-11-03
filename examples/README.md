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
queue to a Lambda function; a daily Lambda function; patching and backups. Each file names the others by name, never by ID.

## Account-wide: `global/shared/`

| Stack | Files | Shows |
|---|---|---|
| `baseline` | none | no settings: the same for every account |
| `dns` | `zones.yml` | public hosted zones; private zones come from `config/global.yml` |
| `iam` | `dashboards.yml`, `runner.yml`, `collector.yml`, `policies/read-revisions.yml`, `policies/read-tags.yml` | a role per kind of server, AWS managed policies, shared customer-managed policies, a statement of a role's own |
| `cloudfront` | `assets.yml` | a private bucket served through CloudFront, with its certificate and WAF |

## The region's shared stacks: `us-east-1/shared/`

| Stack | Files | Shows |
|---|---|---|
| `hub` | none | built from `config/` alone |
| `logging` | `logging.yml` | how long load balancer and WAF logs are kept |
| `ecr` | `ecr.yml` | image repositories and how many images they keep |
| `session-manager` | `session-manager.yml` | idle timeout, session length, log retention |
| `documents` | `install-cloudwatch-agent.yml` | an SSM Command document written as YAML |

## One environment: `us-east-1/development/`

| Stack | Files | Shows |
|---|---|---|
| `network` | none | built from `config/` alone |
| `security-groups` | `dashboards-lb.yml`, `dashboards.yml`, `database.yml`, `files.yml`, `collectors-lb.yml`, `collector.yml`, `runner.yml`, `sqlserver.yml` | a group per role; sources by name (`dashboards-lb`), tier (`tier:ops`), the office (`hq`) and `self`; ports and ranges; tightened egress on the database |
| `endpoints` | `endpoints.yml` | interface and gateway endpoints |
| `keys` | none | two keys per environment, no settings |
| `backups` | `backups.yml` | retention and the copy to another region |
| `certificates` | `certificates.yml` | a DNS-validated certificate with an alternative name |
| `load-balancers` | `internal.yml`, `collectors.yml` | an internal application load balancer answering 404 unless claimed, with a redirect rule; a network load balancer with a target group |
| `waf` | `internal.yml` | a web ACL on a load balancer |
| `databases` | `dashboards.yml` | PostgreSQL, Multi-AZ, storage that grows |
| `storage` | `shared-files.yml` | EFS with an access point |
| `buckets` | `revisions.yml`, `exports.yml` | CodeDeploy revisions that expire; a backed-up bucket with object lock |
| `compute` | `dashboards.yml`, `api.yml`, `collector.yml`, `runner.yml`, `sqlserver.yml` | the shapes of a group: a target group, listener rules, CodeDeploy and DNS records; an Auto Scaling group that tracks CPU; behind a network load balancer; plain; pinned with chosen addresses and a data disk |
| `records` | `runner.yml`, `sql.yml` | an A record to a server, a CNAME |
| `access` | `dashboards-db.yml` | a Session Manager tunnel to the database |
| `patching` | `patching.yml` | the maintenance window and approval delay |
| `lambda` | `report.yml`, `src/report/app.py` | a scheduled function, its permissions and its code |

What each key means is in the stack's own doc under [`docs/`](../docs).
