# What the module builds and refuses, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

variables {
  name        = "production-reports-111111111111-us-east-2"
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  backup      = true
}

run "private_encrypted_versioned" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.bucket.restrict_public_buckets && aws_s3_bucket_ownership_controls.bucket.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Never public, and no ACLs."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.bucket.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Every object encrypted with the environment's data key."
  }

  assert {
    condition     = aws_s3_bucket_versioning.bucket.versioning_configuration[0].status == "Enabled" && aws_s3_bucket.bucket.tags.Backup == "standard"
    error_message = "Versioned, and in the backup plan when asked."
  }

  assert {
    condition     = length(aws_s3_bucket_object_lock_configuration.bucket) == 0 && length(aws_s3_bucket_cors_configuration.bucket) == 0
    error_message = "No object lock or CORS unless asked."
  }
}

run "object_lock" {
  command = plan

  variables {
    object_lock = { mode = "COMPLIANCE", days = 2555 }
  }

  assert {
    condition     = aws_s3_bucket.bucket.object_lock_enabled && one(aws_s3_bucket_object_lock_configuration.bucket[0].rule).default_retention[0].days == 2555
    error_message = "Records locked for seven years."
  }
}

run "rejects_any_origin" {
  command = plan

  variables {
    cors = [{ allowed_methods = ["GET"], allowed_origins = ["*"] }]
  }

  expect_failures = [var.cors]
}
