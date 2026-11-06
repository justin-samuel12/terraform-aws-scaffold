mock_provider "aws" {}

variables {
  name       = "ad.example.internal"
  short_name = "CORP"
  edition    = "Standard"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
}

run "builds_the_directory" {
  command = plan

  assert {
    condition     = aws_directory_service_directory.directory.type == "MicrosoftAD" && aws_directory_service_directory.directory.edition == "Standard" && aws_directory_service_directory.directory.short_name == "CORP"
    error_message = "The directory is AWS Managed Microsoft AD, in the edition asked for."
  }

  assert {
    condition     = aws_secretsmanager_secret.admin.name == "directory/ad.example.internal/admin" && aws_secretsmanager_secret_version.admin.secret_string_wo_version == 1
    error_message = "The Admin password is generated once, into a secret named after the domain."
  }
}

run "rejects_one_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaaaaaaaaaaaaaa1"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_a_long_short_name" {
  command = plan

  variables {
    short_name = "AVERYLONGNETBIOSNAME"
  }

  expect_failures = [var.short_name]
}
