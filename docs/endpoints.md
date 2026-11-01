# VPC endpoints

Each environment's VPC endpoints are a stack of their own:
`live/<region>/<environment>/endpoints/`, configured by one file beside it.

```yaml
# live/us-east-1/development/endpoints/endpoints.yml
tier: private
interface:
  - ssm
  - ssmmessages
  - ec2messages
gateway:
  - s3
```

| Key | Meaning |
|---|---|
| `tier` | The tier whose subnets hold the interface endpoints, one per zone. Default `private`; every tier in the VPC can reach it |
| `interface` | Services reached through interface endpoints, by AWS service name without the `com.amazonaws.<region>.` prefix |
| `gateway` | `s3` or `dynamodb`: gateway endpoints, added to every route table in the VPC |

## Why these

- **`ssm`, `ssmmessages`, `ec2messages`** are what the Systems Manager agent
  needs for Session Manager (access without SSH or RDP open) and Patch Manager.
  Through these endpoints, servers in the `data` tier, which has no route to the
  internet, can still be managed.
- **`s3`** keeps S3 traffic off the NAT gateways, which is cheaper and private,
  and lets the `data` tier reach S3 (backups, patch baselines) without the
  internet.

- **`secretsmanager`** lets applications fetch their secrets without the
  internet.

Others a Windows or Linux fleet commonly needs, added as lines under
`interface`: `logs` (CloudWatch agent), `kms`, `monitoring`, and `ecr.api` with
`ecr.dkr` for pulling container images.

## How they are built

Interface endpoints use private DNS, so a service answers at its usual name
inside the VPC and agents need no settings. They share one security group,
`endpoints`, which accepts only HTTPS from the VPC's own range. Gateway
endpoints are routes: free, and with no security group.

Interface endpoints cost about $0.01 an hour per zone each, plus data: Session
Manager's three in three zones are about $66 a month per VPC. Gateway endpoints
are free.

The `vpc-endpoint` module builds them; the `endpoints` template reads the file,
finds the VPC, its route tables and the tier's subnets by tags, and refuses an
unknown key, a tier the VPC does not have, a gateway service other than `s3`
or `dynamodb`, and interface endpoints in fewer than two zones.
