# Systems Manager

Session Manager, SSM documents and patching, in four stacks: two shared by the
region, two per environment.

| Stack | Holds |
|---|---|
| `live/<region>/shared/session-manager` | the region's Session Manager preferences |
| `live/<region>/shared/documents` | Command and Automation documents every environment uses |
| `live/<region>/<environment>/access` | tunnels to fixed hosts in that environment |
| `live/<region>/<environment>/patching` | that environment's patch baselines and maintenance window |

## `session-manager`

Every session in the region is encrypted with a key of its own (`alias/shared-sessions`,
usable only by Session Manager), streamed to the CloudWatch log group
`/ssm/sessions` (kept 365 days), closed after 20 idle minutes, and never longer
than 8 hours. Optional overrides in `session-manager.yml`:

```yaml
idle_timeout_minutes: 20
max_session_minutes: 480
log_retention_days: 365
```

The stack also turns on **Default Host Management** in its region: every
instance can use Session Manager and Patch Manager whatever its own instance
profile holds, so a server is never unreachable because its role forgot
`AmazonSSMManagedInstanceCore`. It uses one account-wide role,
`service-role/AWSSystemsManagerDefaultEC2InstanceManagementRole`, which only the
primary region's stack creates; every region's setting points at it.

AWS reads these preferences from one document with a fixed name,
`SSM-SessionManagerRunShell`. If anyone has opened the Session Manager
preferences in the console, the account already has it, and it must be
imported before the first apply (see SKILLS.md, import work).

## `documents`

One file per Command or Automation document: the procedures every environment
runs (join a domain, install an agent, build a cluster). The file holds the
document's type and its content, written as YAML.

```yaml
# live/us-east-1/shared/documents/install-cloudwatch-agent.yml
type: Command
content:
  schemaVersion: "2.2"
  description: Install the CloudWatch agent
  mainSteps:
    - action: aws:runDocument
      name: install
      inputs:
        documentType: SSMDocument
        documentPath: AWS-ConfigureAWSPackage
        documentParameters:
          action: Install
          name: AmazonCloudWatchAgent
```

Names may not start with `AWS` (reserved). Prefer AWS's own documents
(`AWS-RunPatchBaseline`, `AWS-ConfigureAWSPackage`) where they do the job.

## `access`

One file per tunnel, to one fixed host and port: a database or cache that
people reach from their own machine.

```yaml
# live/us-east-1/development/access/orders.yml
description: Port forwarding to the development orders database
host: orders.abcdefghijkl.us-east-1.rds.amazonaws.com
port: 5432
local_port: 15432
```

The template writes the Session document (`development-orders`). Fixing the host in
the document, rather than using AWS's generic remote-host document, is what lets
access be granted to this tunnel and nothing wider: whoever may use it gets
`ssm:StartSession` on its ARN (the stack's output) in their Identity Center
permission set. The plan refuses a file without `host` and `port`.

## `patching`

```yaml
# live/us-east-1/development/patching/patching.yml
schedule: cron(0 7 ? * SUN *)
duration_hours: 3
approve_after_days: 7
```

A patch baseline per operating system (Windows, Amazon Linux 2023, Ubuntu)
approving security and critical patches once they are `approve_after_days` old,
so a bad patch can be caught first; the environment as the patch group; and a
maintenance window that runs `AWS-RunPatchBaseline` on every instance tagged
`Patch Group = <environment>`, a quarter at a time, stopping if more than one in
ten fail, rebooting only when a patch needs it, with output in
`/ssm/patching/<environment>` (kept 365 days). Compute tags its instances.

Give production a later window and a longer wait than staging, so staging takes
each patch first.
