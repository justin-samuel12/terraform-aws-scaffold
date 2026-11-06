data "aws_default_tags" "current" {}

data "aws_secretsmanager_random_password" "admin" {
  password_length            = 32
  require_each_included_type = true
  exclude_characters         = "\"'`\\/@ "
}

data "aws_secretsmanager_secret_version" "admin" {
  secret_id  = aws_secretsmanager_secret.admin.id
  version_id = aws_secretsmanager_secret_version.admin.version_id
}
