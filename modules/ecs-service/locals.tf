locals {
  service_name        = "${var.environment}-${var.name}"
  task_role_name      = "${var.environment}-${var.name}-${var.region}"
  execution_role_name = "${var.environment}-${var.name}-${var.region}-execution"
  partition           = data.aws_partition.current.partition
  account_id          = data.aws_caller_identity.current.account_id

  blue_green = var.deployment.strategy == "blue_green"
  routed     = length(var.routes) > 0
  scaled     = var.autoscaling != null
  # The container the load balancer sends traffic to: the first with a port.
  front = try([for c in var.containers : c if c.port != null][0], null)

  # Target group names fit AWS's 32 characters; blue/green has two, which CodeDeploy swaps, rolling one.
  target_keys = local.routed ? (local.blue_green ? ["blue", "green"] : ["primary"]) : []
  target_group_names = {
    for k in local.target_keys : k => "${substr(local.service_name, 0, min(23, length(local.service_name)))}-${substr(sha1("${local.service_name}/${k}/${try(local.front.port, 0)}"), 0, 8)}"
  }
  live_target = try(local.target_keys[0], null)

  container_definitions = [
    for c in var.containers : merge(
      {
        name         = c.name
        image        = c.image
        essential    = c.essential
        portMappings = c.port == null ? [] : [{ containerPort = c.port, protocol = "tcp" }]
        environment  = [for k in sort(keys(c.environment)) : { name = k, value = c.environment[k] }]
        secrets      = [for k in sort(keys(c.secrets)) : { name = k, valueFrom = c.secrets[k] }]
        # An init process reaps zombie processes, and ECS Exec needs it to start its agent cleanly.
        linuxParameters = { initProcessEnabled = true }
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.service.name
            awslogs-region        = var.region
            awslogs-stream-prefix = "ecs"
          }
        }
      },
      c.command == null ? {} : { command = c.command },
      c.health_check == null ? {} : {
        healthCheck = {
          command     = c.health_check.command
          interval    = c.health_check.interval
          timeout     = c.health_check.timeout
          retries     = c.health_check.retries
          startPeriod = c.health_check.start_period
        }
      },
    )
  ]

  # Images from ECR are pulled with the execution role, from their own repositories only.
  ecr_images          = [for c in var.containers : regex("^([0-9]{12})\\.dkr\\.ecr\\.([a-z0-9-]+)\\.amazonaws\\.com/([^:@]+)", c.image) if can(regex("^[0-9]{12}\\.dkr\\.ecr\\.", c.image))]
  ecr_repository_arns = distinct([for m in local.ecr_images : "arn:${local.partition}:ecr:${m[1]}:${m[0]}:repository/${m[2]}"])

  # A secret's ARN may end in :<json-key>:<stage>:<version>; the permission is on the secret itself.
  secret_arns     = distinct(flatten([for c in var.containers : values(c.secrets)]))
  secrets_manager = distinct([for a in local.secret_arns : join(":", slice(split(":", a), 0, 7)) if split(":", a)[2] == "secretsmanager"])
  parameters      = [for a in local.secret_arns : a if split(":", a)[2] == "ssm"]

  execution_statements = concat(
    flatten([for arns in(length(local.ecr_repository_arns) == 0 ? [] : [local.ecr_repository_arns]) : [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = ["*"] },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = arns },
    ]]),
    [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = ["${aws_cloudwatch_log_group.service.arn}:*"] }],
    [for arns in(length(local.secrets_manager) == 0 ? [] : [local.secrets_manager]) : { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = arns }],
    [for arns in(length(local.parameters) == 0 ? [] : [local.parameters]) : { Effect = "Allow", Action = ["ssm:GetParameters"], Resource = arns }],
    [for arns in(length(local.secret_arns) == 0 ? [] : [local.secret_arns]) : {
      Effect    = "Allow"
      Action    = ["kms:Decrypt"]
      Resource  = ["*"]
      Condition = { StringEquals = { "kms:ViaService" = sort(distinct([for a in arns : "${split(":", a)[2]}.${split(":", a)[3]}.amazonaws.com"])) } }
    }],
  )

  task_statements = concat(
    [for s in var.statements : { Effect = s.effect, Action = s.actions, Resource = s.resources }],
    flatten([for e in(var.execute_command == null ? [] : [var.execute_command]) : [
      { Effect = "Allow", Action = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"], Resource = ["*"] },
      { Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = ["*"] },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"], Resource = ["${e.log_group_arn}:*"] },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [e.kms_key_arn] },
    ]]),
  )

  # Only ECS, for tasks in this account, may take either role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })

  network = {
    subnets         = var.subnet_ids
    security_groups = var.security_group_ids
  }
}
