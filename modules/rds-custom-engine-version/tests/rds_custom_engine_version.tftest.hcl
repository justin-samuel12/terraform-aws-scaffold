mock_provider "aws" {}

variables {
  engine          = "custom-sqlserver-se"
  engine_version  = "16.00.4185.3.dbamp-v1"
  source_image_id = "ami-0123456789abcdef0"
  description     = "SQL Server 2022 Standard with DBAmp"
}

run "from_an_image" {
  command = plan

  assert {
    condition     = aws_rds_custom_db_engine_version.engine_version.source_image_id == "ami-0123456789abcdef0" && output.engine_version == "16.00.4185.3.dbamp-v1"
    error_message = "A version made from our image, named as databases will name it."
  }
}

run "rejects_an_aws_version_name" {
  command = plan

  variables {
    engine_version = "16.00.4185.3.v1"
  }

  expect_failures = [var.engine_version]
}

run "rejects_a_standard_rds_engine" {
  command = plan

  variables {
    engine = "sqlserver-se"
  }

  expect_failures = [var.engine]
}
