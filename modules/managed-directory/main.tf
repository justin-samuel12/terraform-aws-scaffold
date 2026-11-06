resource "aws_secretsmanager_secret" "admin" {
  name                    = "directory/${var.name}/admin"
  description             = "The Admin password of ${var.name}, set when the directory is created and never read back into a plan."
  recovery_window_in_days = 30

  tags = { Name = "${local.name_prefix}Directory Admin ${var.name}" }
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id                = aws_secretsmanager_secret.admin.id
  secret_string_wo         = data.aws_secretsmanager_random_password.admin.random_password
  secret_string_wo_version = 1
}

resource "aws_directory_service_directory" "directory" {
  name        = var.name
  short_name  = var.short_name
  type        = "MicrosoftAD"
  edition     = var.edition
  description = var.description
  password    = data.aws_secretsmanager_secret_version.admin.secret_string

  vpc_settings {
    vpc_id     = var.vpc_id
    subnet_ids = var.subnet_ids
  }

  tags = { Name = "${local.name_prefix}Directory ${var.name}" }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password]
  }
}
