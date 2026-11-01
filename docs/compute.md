# Compute

Servers and what points at them are split by kind, so a change to a redirect
cannot touch a server and a server rebuild cannot touch DNS:

| What | Where |
|---|---|
| Applications: stateless servers, their target group, routes, CodeDeploy and DNS names | `live/<region>/<environment>/apps/`, one file per application |
| Every other server | `live/<region>/<environment>/compute/`, one file per group of servers |
| Load balancers, listeners, their own rules, network load balancer targets | the `load-balancers` stack ([load balancers](load-balancers.md)) |
| DNS names for anything that is not an application | `live/<region>/<environment>/records/`, one file per name |
| Certificates | the `certificates` stack ([global](global.md#certificates)) |
| Images | pinned by ID in each file; building them is not included ([day one](day-one.md)) |

These stacks are scaffolding: they exist, validate, and build nothing until a
file is added.

Two stacks hold servers. **`apps`** is for applications: stateless servers
behind a load balancer or deployed by CodeDeploy, where everything about one
application sits in one file. **`compute`** is for every other server: SQL
Server, domain controllers, runners, anything holding state.

## `compute`: groups of servers

One file per group. A group says what its servers share and how many there are;
its members are named `<group>-01`, `<group>-02` and so on, and any member can
be pinned or changed.

```yaml
# live/us-east-1/development/compute/runner.yml
count: 3
type: c6i.large
image: ami-0123456789abcdef0
tier: ops
security_groups:
  - runner
role: runner
```

```yaml
# live/us-east-1/production/compute/sqlserver.yml
count: 2
type: r6i.2xlarge
image: ami-0123456789abcdef0
security_groups:
  - sqlserver
role: sqlserver
protect: true
volumes:
  data:
    device: /dev/sdf
    size: 1000
    iops: 6000
    throughput: 500
members:
  sqlserver-01:
    subnet: data-az1
    ips:
      primary: 70
      cluster: 71
      listener: 72
  sqlserver-02:
    subnet: data-az2
    ips:
      primary: 70
      cluster: 71
      listener: 72
```

| Key | Meaning |
|---|---|
| `count` | How many servers; adding one adds `<group>-NN` and touches nothing else, removing one removes only the last |
| `type` | The instance type; a member can override it |
| `image` | An AMI id, pinned. A new image is rolled out by changing it, group by group, deliberately; the plan refuses a name or a search |
| `tier` | Where unpinned members go: spread across the region's zones in turn (`ops-az1`, `ops-az2`, …). Default `private` |
| `security_groups` | From the environment's security-groups stack, by name |
| `role` | Required: an instance profile from the `iam` stack, by name, so every server's permissions are chosen. The plan refuses a group without one |
| `root_size`, `volumes` | Root disk GB (default 30); extra disks by name, device, GB, IOPS, throughput |
| `protect` | For servers holding state: termination and stop protection, and no plan may destroy them or their disks. Every member must be pinned to a subnet |
| `backup` | In the environment's AWS Backup plan (default `true`) |
| `user_data` | A boot script beside the file. Never secrets: user data is readable by anyone who can describe the instance |
| `targets` | `<load balancer>/<target>: <port>`: every server is registered with that target group |
| `members` | Per server: `subnet` (`data-az1`), `type`, and `ip` or `ips` |
| `tags` | Extra tags |

Built in, for every server: IMDSv2 only, no SSH key (access is Session
Manager, which works on every server through Default Host Management,
[systems manager](systems-manager.md#session-manager), whatever its role holds), no public address, root and data disks encrypted with the
environment's data key, detailed monitoring, automatic recovery, and the tags
`Patch Group = <environment>` (patching) and `Backup = standard`.

## Rebuilding a server

When Terraform destroys or rebuilds a server, the steps run in this order:

1. it leaves every target group, draining for 60 seconds;
2. its extra disks are detached at once, without waiting for the OS
   (`force_detach`), so a mounted disk cannot hold the rebuild up;
3. it is powered off at once, without an OS shutdown
   (`aws ec2 terminate-instances --skip-os-shutdown`);
4. the new server is built, its disks attached, and it joins its target groups.

A rebuild happens when `image` or `type` changes in a way AWS cannot make in
place, when a member moves subnet, on `-replace`, or when a server is removed.
Nothing is flushed and no service stops cleanly, so a disk that is reattached
comes back as after a power cut. Servers with `protect: true` are never
destroyed by a plan, so none of this applies to them.

The AWS provider has no setting for step 3. A destroy-time step runs the AWS CLI
with the stack's profile (`bin/tf` passes it on). If the CLI is missing, too old
(`make setup` warns), or refused, Terraform's own terminate still runs, with the
usual slower OS shutdown, so the destroy never fails because of the shortcut.

Target groups rebuild the other way round: the new group is built first and
every listener and rule moves to it in place (see
[load balancers](load-balancers.md#built-in)). When a group in the
load-balancers stack is rebuilt, the servers that join it from compute or
`apps` (`targets:`) move to the new one only on that stack's next apply, so
apply it straight after. An application's own target group has no such gap:
it lives in the same plan as its servers and routes.

## Addresses: AWS-assigned, or chosen and identical everywhere

By default AWS assigns each server an address. Where something needs a stable
address (a SQL Server cluster and listener, a partner's allow list), a member
names a host number in its subnet: `ip: 70`, or `ips:` with `primary` and any
extra addresses. Because every environment's VPC is carved identically, the same
file gives the same address everywhere but the second octet:

| | `subnet: ops-az1`, `ip: 70` |
|---|---|
| development, us-east-1 | 10.41.228.70 |
| staging, us-east-1 | 10.42.228.70 |
| production, us-east-1 | 10.43.228.70 |
| production's disaster-recovery copy, us-west-2 | 10.63.228.70 |

Chosen addresses come from a block every subnet reserves: `.64` to `.127` of
its first /24 (`reserved: 26` per tier in `config/global.yml`). The block is a
subnet CIDR reservation of type explicit, so AWS never hands one of its
addresses to anything on its own; load balancers, endpoints, databases and
servers without `ip` take addresses from the rest of the subnet, and a chosen
address can never be taken first. The plan refuses an address outside the block
and an address chosen twice.

## `apps`: one file per application

Everything one application needs, in one file: its servers, how the load
balancer reaches them, how its code is deployed, and its DNS names. What
several applications share stays in its own stack: load balancers and
listeners (load-balancers), certificates, security groups, zones and roles.

```yaml
# live/us-east-1/development/apps/web.yml
servers:
  count: 2
  type: t3.medium
  image: ami-0123456789abcdef0
  tier: ops
  role: web
  security_groups:
    - web
port: 3000
health: /api/health
routes:
  - load_balancer: internal
    hosts:
      - app.example.com
    priority: 1010
deploy: one-at-a-time
names:
  - name: web
    zone: example.com
    private: true
```

```yaml
# live/us-east-1/development/apps/collector.yml   (behind a network load balancer, no CodeDeploy)
servers:
  count: 1
  type: t3.small
  image: ami-0123456789abcdef0
  tier: ops
  role: collector
targets:
  internal-nlb/collector: 10051
```

| Key | Meaning |
|---|---|
| `servers` | Like a compute group (`count`, `type`, `image`, `tier`, `role`, `security_groups`, `root_size`, `volumes`, `backup`, `user_data`, `members`, `tags`), with servers named `<application>-01` and so on. No `protect`: an application's servers can be rebuilt at any time |
| `port`, `health` | The port it listens on and the path the load balancer checks (default `/`). `port` is required with `routes` |
| `target` | Its own target group's settings: `protocol` (`HTTP`, or `HTTPS` to servers that terminate TLS themselves), `matcher` (healthy codes, default `200-399`), `stickiness` (seconds; leave out for none), `slow_start` (seconds, 30 to 900) |
| `routes` | Rules on a shared load balancer's listener: `load_balancer` by name, `listener` port (default 443), `hosts` and/or `paths`, and a `priority` from 1000 up (1 to 999 are the load balancer's own rules). `paths: ["/*"]` at the highest priority number takes everything left over |
| `targets` | `<load balancer>/<target>: <port>`: a network load balancer's target groups its servers also join, from the load-balancers stack |
| `deploy` | `one-at-a-time`, `half-at-a-time` or `all-at-once`. Leave it out and CodeDeploy never touches the application |
| `names` | DNS aliases to the application's load balancer: `name`, `zone`, `private`, and `load_balancer` when it is not the first route's |

With `routes`, the application gets a target group of its own,
`app-<application>-<suffix>` (so the name is 23 characters at most), its
servers are registered in it, and each route forwards to it. The plan refuses two routes,
in any application, with the same priority on one listener or claiming the same
host and path.

With `deploy`, the application gets a CodeDeploy application named
`<environment>-<application>` and a deployment group named after the
environment, which finds its servers by two tags that must both match,
`Environment` and `Application`, so a deployment cannot reach another
environment's servers or another application's. Applications behind a load balancer
deploy with traffic control: each server leaves every target group it is in,
its own and any network load balancer's, while it is updated. Every deployment
rolls back by itself on failure. The environment's
CodeDeploy service role, `codedeploy-<environment>`, is created by this stack
when the first application sets `deploy`.

What a deployed application also needs, outside this stack:

- the **CodeDeploy agent in its image**;
- a **revisions bucket**: a file in the environment's `buckets` stack (for
  example `buckets/revisions.yml`), where the build uploads each release;
- **read access to it in the application's role**: a shared policy in the iam
  stack, `policies/read-revisions.yml`, allowing `s3:GetObject` on that
  bucket's objects, listed under each deployed application's role;
- a **role for the CI system** to upload and start deployments (not included:
  it depends on the CI system, see [day one](day-one.md)).

Changing `image` rebuilds the servers; a deployment changes only the code on
them. Roll a new image out deliberately, one application at a time.

## `records`: DNS names

One file per name, pointing at a load balancer, a server, or another name.

```yaml
# live/us-east-1/production/records/api.yml
zone: example.com
load_balancer: external
```

```yaml
# live/us-east-1/development/records/web.yml
zone: internal.example.com
private: true
server: web-01
```

| Key | Meaning |
|---|---|
| `zone` | The hosted zone; `private: true` for a private zone |
| `name` | The record's name in the zone; default the file name |
| `load_balancer` | An alias to that load balancer, following its health |
| `server` | An A record to that server's private address |
| `cname` | A CNAME to another name |

Zones are the global `dns` stack's; records belong to the environment that owns
what they point at. An application's own names go in its `apps` file instead.
