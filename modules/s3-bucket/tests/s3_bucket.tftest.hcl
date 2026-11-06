mock_provider "aws" {}

variables {
  name        = "production-reports-111111111111-us-east-2"
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  tags        = { Backup = "standard" }
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
    condition     = aws_s3_bucket_versioning.bucket.versioning_configuration[0].status == "Enabled" && aws_s3_bucket.bucket.tags.Backup == "standard" && aws_s3_bucket.bucket.tags.Name == "production-reports-111111111111-us-east-2"
    error_message = "Versioned, with the tags it was given and its name."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.bucket) == 0 && length(aws_s3_bucket_object_lock_configuration.bucket) == 0 && length(aws_s3_bucket_cors_configuration.bucket) == 0
    error_message = "No lifecycle rules, object lock or CORS unless written."
  }
}

run "lifecycle_rules" {
  command = plan

  variables {
    lifecycle_rule = [
      { id = "versions", status = "Enabled", noncurrent_version_expiration = { noncurrent_days = 90 }, abort_incomplete_multipart_upload = { days_after_initiation = 7 } },
      { id = "exports", status = "Enabled", filter = { prefix = "exports/" }, expiration = { days = 400 } },
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.bucket[0].rule) == 2 && aws_s3_bucket_lifecycle_configuration.bucket[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == 90 && aws_s3_bucket_lifecycle_configuration.bucket[0].rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7 && length(aws_s3_bucket_lifecycle_configuration.bucket[0].rule[0].expiration) == 0
    error_message = "A rule has only what it was given."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.bucket[0].rule[1].filter[0].prefix == "exports/" && aws_s3_bucket_lifecycle_configuration.bucket[0].rule[1].expiration[0].days == 400
    error_message = "A filter narrows a rule to a prefix."
  }
}

run "object_lock" {
  command = plan

  variables {
    object_lock_enabled       = true
    object_lock_configuration = { rule = { default_retention = { mode = "COMPLIANCE", days = 2555 } } }
  }

  assert {
    condition     = aws_s3_bucket.bucket.object_lock_enabled && one(aws_s3_bucket_object_lock_configuration.bucket[0].rule).default_retention[0].days == 2555
    error_message = "Records locked for seven years."
  }
}

run "rejects_object_lock_without_enabling_it" {
  command = plan

  variables {
    object_lock_configuration = { rule = { default_retention = { mode = "COMPLIANCE", days = 2555 } } }
  }

  expect_failures = [var.object_lock_configuration]
}

run "rejects_any_origin" {
  command = plan

  variables {
    cors_rule = [{ allowed_methods = ["GET"], allowed_origins = ["*"] }]
  }

  expect_failures = [var.cors_rule]
}
