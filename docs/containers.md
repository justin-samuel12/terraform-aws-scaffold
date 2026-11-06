# Containers

`live/<region>/<environment>/containers` runs an environment's containerised
applications on ECS with Fargate, one `.yml` file per service. It comes after
`network`, `security-groups` and `keys`, and after `load-balancers` when a
service is routed through one. The files sit in `config/` below the stack's
`.tf` files, in any folders under it; a file name used twice is refused. With no files it builds nothing, not even the
cluster.

ECS is AWS's container scheduler: you describe a task (one or more containers,
how much CPU and memory, which ports) and how many copies of it should run, and
ECS keeps that many running. Fargate is where they run: AWS supplies the
machine for each task, so there are no servers to patch, size or scale. Each
task gets its own network interface in a private subnet, with its own security
groups, exactly like a server would.

```mermaid
flowchart LR
  lb["🔀 internal load balancer<br/>listener 443"] -->|orders.example.com| tg1["🎯 primary"]
  lb -->|checkout.example.com| tg2["🎯 blue / green"]
  tg1 --> s1["📦 development-orders-api<br/>rolling"]
  tg2 --> s2["📦 development-checkout<br/>blue/green"]
  cd["🚀 CodeDeploy<br/>development-checkout"] -.->|moves traffic| tg2
  s1 & s2 --- cluster["🗄️ cluster: development"]

  classDef s fill:#e8f1fb,stroke:#2f6fb3,color:#0b2545
  classDef c fill:#f3f0ff,stroke:#6741d9,color:#25125e
  class s1,s2 s
  class cluster,cd c
```

## What every environment gets

One cluster per environment and region, named after the environment
(`development`). It has Container Insights on, Fargate and Fargate Spot to run
on (Fargate unless a service says otherwise), and ECS Exec set up: sessions
into a container are encrypted with the environment's data key and every
command is logged to `/ecs/<environment>/exec` for a year.

## A file

A file is one service, named `<environment>-<file>`: `config/orders-api.yml`
in development is the service, task definition family and log group
`development-orders-api`. Its keys are the arguments of `aws_ecs_service` and
`aws_ecs_task_definition`, with the provider's names and shapes, plus the
target group's health check, the listener rule, scaling and the CodeDeploy
group. A key that is none of these is refused. What a file leaves out is the
provider's default, not one of this stack's.

```yaml
# live/us-east-1/development/containers/config/orders-api.yml
cpu: 512
memory: 1024
desired_count: 2
enable_execute_command: true
network_configuration:
  subnets:
    - private-az1
    - private-az2
    - private-az3
  security_groups:
    - orders-api
container_definitions:
  - name: orders-api
    image: 111111111111.dkr.ecr.us-east-1.amazonaws.com/orders-api:1.4.2
    portMappings:
      - containerPort: 8080
    environment:
      - name: LOG_LEVEL
        value: info
    secrets:
      - name: DATABASE_URL
        valueFrom: arn:aws:secretsmanager:us-east-1:111111111111:secret:development/orders-api/database-AbCdEf
target_group:
  health_check:
    path: /health
listener_rule:
  listener_arn: internal/443
  priority: 1300
  condition:
    host_header:
      values:
        - orders.example.com
```

| Key | Meaning |
|---|---|
| `cpu`, `memory` | Required. The whole task's size: CPU units (1024 is one vCPU: 256, 512, 1024, 2048, 4096, 8192 or 16384) and MiB, in the range Fargate allows for that CPU |
| `desired_count` | Required. How many tasks run; with `appautoscaling_target`, how many it starts with. Either way the count is held by Application Auto Scaling (at `desired_count`, or within its range), so adding or removing `appautoscaling_target` later changes it in place and never replaces the running service |
| `network_configuration` | `subnets`, by name such as `private-az1` (the VPC's subnets, `<tier>-az<n>`), and `security_groups`, by name from the security-groups stack, one to five. An ID (`subnet-…`, `sg-…`) passes through unchanged. Tasks never get a public address |
| `container_definitions` | Required: the task's containers, in the task definition's own names. Each has `name` (unique in the file) and `image`, and may have `essential`, `command`, `portMappings` (each a `containerPort`), `environment` (each `name` and `value`), `secrets` (each `name` and `valueFrom`) and `healthCheck` (`command`, `interval`, `timeout`, `retries`, `startPeriod`). The first container with a port takes the load balancer's traffic. Logging to the service's log group and an init process are added to every container |
| `environment` | Plain settings, never secrets: a name that looks like one (`PASSWORD`, `TOKEN`, `API_KEY`…) is refused |
| `secrets` | `valueFrom` is the ARN of a Secrets Manager secret (optionally `:<json-key>::`) or a Parameter Store parameter. ECS reads it when the task starts and hands the container the value; the value is never in Terraform, the plan or the task definition |
| `runtime_platform` | `cpu_architecture` (`X86_64` or `ARM64`, cheaper, if the image is built for it) and `operating_system_family`. Without it, Fargate's own: X86_64 Linux |
| `capacity_provider_strategy` | `FARGATE` and `FARGATE_SPOT`, each with `weight` and `base`. Spot is much cheaper and can be taken back with two minutes' notice, so it suits workers that can stop. Without it, `FARGATE` |
| `enable_execute_command` | ECS Exec into its containers; off unless `true`, as in the provider |
| `deployment_minimum_healthy_percent`, `deployment_maximum_percent` | As in `aws_ecs_service`; without them, the provider's (100 and 200) |
| `deployment_controller` | `type`: `ECS` (the provider's default) or `CODE_DEPLOY` ([Deployments](#deployments)) |
| `deployment_group` | With `CODE_DEPLOY` only, the `aws_codedeploy_deployment_group`'s `deployment_config_name` (required) and `blue_green_deployment_config.terminate_blue_instances_on_deployment_success.termination_wait_time_in_minutes` |
| `statement` | The application's own permissions: `actions` and `resources`, with `effect` and `condition` (each `test`, `variable`, `values`) if wanted. `{app}`, `{environment}` and `{region}` are filled in |
| `tags` | Extra tags on everything the service builds, over the provider's defaults. `Name` and `Service` are the stack's own and refused |
| `target_group` | `health_check`, the load balancer's check: `path`, `matcher`, `interval`, `timeout`, `healthy_threshold`, `unhealthy_threshold`, each the provider's default when left out. Needs a `listener_rule` |
| `listener_rule` | As in compute, an `aws_lb_listener_rule` with its keys: `listener_arn` as `<load balancer>/<port>` (`services/443`, a load-balancers stack's file name and a listener's port), a `priority` of 1000 or more, and `condition`: `host_header.values` and/or `path_pattern.values` |
| `appautoscaling_target` | `min_capacity` and `max_capacity` |
| `appautoscaling_policy` | `target_tracking_scaling_policy_configuration`: `target_value` and `predefined_metric_specification.predefined_metric_type` (`ECSServiceAverageCPUUtilization`, `ECSServiceAverageMemoryUtilization` or `ALBRequestCountPerTarget`) |

A service without a `listener_rule` is a worker: no target group, nothing
reaches it from a load balancer. Give it a name with the `records` stack when
it has one, pointing at the load balancer as any other name does.

Listener rule priorities share the listener with compute's groups, so pick
numbers no group uses (the plan checks this stack's own; AWS refuses a clash
between stacks when it is applied).

## On a blueprint

A service can instead name a blueprint and give only what makes it itself:
`blueprint: ecs-service/v1`, its `container_definitions` and its listener
rule. The blueprint fixes the rest (ARM, the private subnets, the
`ecs-services` group, a health check at `/{app}/status`, CodeDeploy canary
deploys, CPU scaling), and the app may change `cpu`, `memory`,
`desired_count`, its scaling range and its security groups
([blueprints](blueprints.md#containers)).

## Two roles per application

Every service has two roles, both assumable only by ECS tasks in this account.

| Role | Name | What it may do |
|---|---|---|
| Execution role | `<environment>-<app>-<region>-execution` | What ECS does before the app starts: pull the image from its own ECR repository, write the service's logs, read exactly the secrets listed in its file. Nothing else |
| Task role | `<environment>-<app>-<region>` | What the application's code does: the file's `statement`, plus ECS Exec's channel and log group when it is on |

The task role matters beyond its permissions. It is the application's
identity: when a container logs in to Vault with AWS auth, Vault sees this role
and so knows `orders-api` from `checkout`, the same way a server on a blueprint
is told apart by its own role ([blueprints](blueprints.md)). Roles are global,
so the name carries the region.

Logs go to `/ecs/<environment>-<app>`, kept 365 days.

## Deployments

A new version is a new task definition: a changed image tag, environment
variable or size. How it reaches the running service depends on
`deployment_controller.type`.

**`ECS`** (the default) is ECS's own rolling deployment. ECS starts new tasks, waits for the
load balancer to call them healthy, then stops old ones, a few at a time,
never dropping below `deployment_minimum_healthy_percent`. Traffic shifts as tasks swap:
for a while both versions answer. If new tasks keep failing, the circuit
breaker stops the deployment and rolls back to the last version that worked.
Changing the file and applying is the deployment.

**`CODE_DEPLOY`** hands deployments to CodeDeploy, blue/green. The service has two target
groups, blue and green. CodeDeploy starts the new version in the idle one,
waits for it to be healthy, then moves the listener rule's traffic across, and
keeps the old tasks for `termination_wait_time_in_minutes` (the provider's
default, 0, when left out) so a rollback is instant. How the traffic moves is
`deployment_group.deployment_config_name`, which has no default:

| `deployment_config_name` | How traffic moves |
|---|---|
| `CodeDeployDefault.ECSAllAtOnce` | All of it, as soon as the new tasks are healthy |
| `CodeDeployDefault.ECSCanary10Percent5Minutes`, `…Canary10Percent15Minutes` | 10% first, the rest after 5 (or 15) minutes if nothing failed |
| `CodeDeployDefault.ECSLinear10PercentEvery1Minutes`, `…Every3Minutes` | 10% more every 1 (or 3) minutes |
| a custom configuration's name | Whatever it says |

A failed deployment, or one stopped by hand, rolls back by itself.

With blue/green, Terraform registers each new task definition but does not put
it into service; that is a deployment's job. A pipeline runs
`aws deploy create-deployment` against application and deployment group
`<environment>-<app>` (the stack's `services` output lists them), with an
AppSpec naming the new task definition, the container and the port. CodeDeploy
also owns which target group is live, so Terraform leaves the service's load
balancer and the listener rule's target alone after creating them.

The plan refuses a `deployment_group` on an `ECS` service (canary and linear
exist only with CodeDeploy), `CODE_DEPLOY` without a `deployment_config_name`,
a server configuration such as `CodeDeployDefault.OneAtATime` on a service,
`CODE_DEPLOY` without a `listener_rule`, and scaling on
`ALBRequestCountPerTarget` with `CODE_DEPLOY` (the target group it would count
is swapped at every deployment).

## How it relates to compute

[Compute](compute.md) runs applications on EC2 servers you size and patch, and
CodeDeploy deploys onto those servers in place, by their `CodeDeploy` tag.
Containers run on Fargate: there are no servers, a deployment replaces whole
tasks, and nothing is installed onto anything.

|  | Compute (EC2) | Containers (Fargate) |
|---|---|---|
| Unit | A server, or an Auto Scaling group | A task: one or more containers |
| Identity | Instance profile; a role per app on a blueprint | Always a task role per app |
| Target group | Instances, `<env>-<group>-<hash>` | Task IPs, `<env>-<app>-<hash>` (two with `CODE_DEPLOY`) |
| Routing | `listener_rule`, priority 1000 and up | The same, on the same listeners |
| CodeDeploy | Compute platform Server, one application name in every environment, deployment groups per branch, in place | Compute platform ECS, application and group `<env>-<app>`, `CODE_DEPLOY` only |
| Rolling out | `deployment_config_name` such as `OneAtATime` | `ECS` rolling, or `CODE_DEPLOY` all at once, canary or linear |
| CodeDeploy role | `codedeploy-<environment>-<region>` | `codedeploy-ecs-<environment>-<region>`, made when a service is `CODE_DEPLOY` |

Both can sit behind the same load balancer: a host can move from a server
group to a service by moving its listener rule from one file to the other.
