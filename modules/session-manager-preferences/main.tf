resource "aws_cloudwatch_log_group" "sessions" {
  name              = "/ssm/sessions"
  retention_in_days = var.log_retention_days

  tags = { Name = "ssm-sessions" }
}

# The account's Session Manager preferences: AWS reads this one document, by this exact name, for every session in the region.
resource "aws_ssm_document" "preferences" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences: encrypted, logged, time-limited"
    sessionType   = "Standard_Stream"
    inputs = {
      kmsKeyId                    = var.kms_key_arn
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sessions.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      s3BucketName                = ""
      idleSessionTimeout          = tostring(var.idle_timeout_minutes)
      maxSessionDuration          = tostring(var.max_session_minutes)
      runAsEnabled                = false
      shellProfile                = { linux = "", windows = "" }
    }
  })

  tags = { Name = "session-manager-preferences" }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

# Default Host Management: every instance can use Session Manager and Patch Manager whatever its own instance profile holds.
resource "aws_iam_role" "default_host" {
  count = var.create_default_host_role ? 1 : 0

  name = "AWSSystemsManagerDefaultEC2InstanceManagementRole"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ssm.amazonaws.com" } }]
  })

  tags = { Name = "ssm-default-host-management" }
}

resource "aws_iam_role_policy_attachment" "default_host" {
  count = var.create_default_host_role ? 1 : 0

  role       = aws_iam_role.default_host[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
}

resource "aws_ssm_service_setting" "default_host" {
  setting_id    = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
  setting_value = "service-role/AWSSystemsManagerDefaultEC2InstanceManagementRole"

  depends_on = [aws_iam_role_policy_attachment.default_host]
}
