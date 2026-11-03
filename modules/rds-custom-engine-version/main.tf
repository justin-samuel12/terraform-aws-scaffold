# A version of SQL Server on an image we built, for RDS Custom databases to run; one in use cannot be deleted.
resource "aws_rds_custom_db_engine_version" "engine_version" {
  engine          = var.engine
  engine_version  = var.engine_version
  source_image_id = var.source_image_id
  description     = var.description

  tags = { Name = "${var.engine}-${var.engine_version}" }
}
