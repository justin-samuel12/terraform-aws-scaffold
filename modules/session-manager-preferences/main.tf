resource "aws_cloudwatch_log_group" "sessions" {
  count = var.log_group == null ? 0 : 1

  name              = "/ssm/sessions"
  retention_in_days = var.log_group.retention_in_days

  tags = merge(var.log_group.tags, { Name = "${local.name_prefix}ssm-sessions" })
}

resource "aws_ssm_document" "preferences" {
  count = var.document == null ? 0 : 1

  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences: encrypted, logged, time-limited"
    sessionType   = "Standard_Stream"
    inputs = {
      kmsKeyId                    = var.kms_key_arn
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sessions[0].name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      s3BucketName                = ""
      idleSessionTimeout          = var.document.content.inputs.idleSessionTimeout
      maxSessionDuration          = var.document.content.inputs.maxSessionDuration
      runAsEnabled                = false
      shellProfile                = { linux = "", windows = "" }
    }
  })

  tags = merge(var.document.tags, { Name = "${local.name_prefix}session-manager-preferences" })

  lifecycle {
    precondition {
      condition     = var.log_group != null
      error_message = "Session Manager's preferences stream every session to /ssm/sessions: give log_group too."
    }
  }
}

resource "aws_iam_role" "default_host" {
  count = var.create_default_host_role ? 1 : 0

  name                 = "AWSSystemsManagerDefaultEC2InstanceManagementRole"
  permissions_boundary = try(var.role_boundary.permissions_boundary, null)
  path                 = "/service-role/"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ssm.amazonaws.com" } }]
  })

  tags = { Name = "${local.name_prefix}ssm-default-host-management" }
}

resource "aws_iam_role_policy_attachment" "default_host" {
  count = var.create_default_host_role ? 1 : 0

  role       = aws_iam_role.default_host[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
}

resource "aws_iam_role_policy" "default_host_sessions" {
  count = var.create_default_host_role ? 1 : 0

  name = "session-manager"
  role = aws_iam_role.default_host[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource  = "*"
        Condition = { "ForAnyValue:StringLike" = { "kms:ResourceAliases" = ["alias/*-sessions"] } }
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = "arn:${data.aws_partition.current.partition}:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/ssm/sessions:*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_ssm_service_setting" "default_host" {
  setting_id    = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
  setting_value = "service-role/AWSSystemsManagerDefaultEC2InstanceManagementRole"

  depends_on = [aws_iam_role_policy_attachment.default_host]
}
