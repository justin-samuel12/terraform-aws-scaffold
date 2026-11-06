resource "aws_rds_custom_db_engine_version" "engine_version" {
  engine          = var.engine
  engine_version  = var.engine_version
  source_image_id = var.source_image_id
  description     = var.description

  tags = { Name = "${local.name_prefix}${var.engine}-${var.engine_version}" }
}
