locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  service_name        = "${var.environment}-${var.name}"
  task_role_name      = "${var.environment}-${var.name}-${var.region}"
  execution_role_name = "${var.environment}-${var.name}-${var.region}-execution"
  partition           = data.aws_partition.current.partition
  account_id          = data.aws_caller_identity.current.account_id

  blue_green = var.deployment_controller == "CODE_DEPLOY"
  routed     = length(var.routes) > 0
  scaled     = var.autoscaling != null
  front      = try([for c in var.container_definitions : { name = c.name, port = c.portMappings[0].containerPort } if length(c.portMappings) > 0][0], null)

  target_keys = local.routed ? (local.blue_green ? ["blue", "green"] : ["primary"]) : []
  target_group_names = {
    for k in local.target_keys : k => "${substr(local.service_name, 0, min(23, length(local.service_name)))}-${substr(sha1("${local.service_name}/${k}/${try(local.front.port, 0)}"), 0, 8)}"
  }
  live_target = try(local.target_keys[0], null)

  container_definitions = [
    for c in var.container_definitions : merge(
      { for k, v in c : k => v if v != null && k != "healthCheck" },
      c.healthCheck == null ? {} : { healthCheck = { for k, v in c.healthCheck : k => v if v != null } },
      {
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
    )
  ]

  ecr_images          = [for c in var.container_definitions : regex("^([0-9]{12})\\.dkr\\.ecr\\.([a-z0-9-]+)\\.amazonaws\\.com/([^:@]+)", c.image) if can(regex("^[0-9]{12}\\.dkr\\.ecr\\.", c.image))]
  ecr_repository_arns = distinct([for m in local.ecr_images : "arn:${local.partition}:ecr:${m[1]}:${m[0]}:repository/${m[2]}"])

  secret_arns     = distinct(flatten([for c in var.container_definitions : [for s in c.secrets : s.valueFrom]]))
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
    [for s in var.statements : merge(
      { Effect = s.effect, Action = s.actions, Resource = s.resources },
      length(s.condition) == 0 ? {} : { Condition = { for test in distinct([for c in s.condition : c.test]) : test => { for c in s.condition : c.variable => c.values if c.test == test } } },
    )],
    flatten([for e in(var.execute_command == null ? [] : [var.execute_command]) : [
      { Effect = "Allow", Action = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"], Resource = ["*"] },
      { Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = ["*"] },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"], Resource = ["${e.log_group_arn}:*"] },
      { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [e.kms_key_arn] },
    ]]),
  )

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })

}
