data "aws_default_tags" "current" {}

data "aws_region" "current" {}

data "archive_file" "code" {
  type             = "zip"
  source_dir       = var.source_dir
  output_path      = "${path.root}/.terraform/lambda/${var.name}.zip"
  output_file_mode = "0644"
}
