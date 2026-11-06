resource "aws_s3_bucket" "bucket" {
  bucket              = var.name
  object_lock_enabled = var.object_lock_enabled

  tags = merge(var.tags, { Name = "${local.name_prefix}${local.short_name}" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  count = length(var.lifecycle_rule) > 0 ? 1 : 0

  bucket = aws_s3_bucket.bucket.id

  dynamic "rule" {
    for_each = var.lifecycle_rule
    content {
      id     = rule.value.id
      status = rule.value.status

      filter {
        prefix = try(rule.value.filter.prefix, null)
      }

      dynamic "expiration" {
        for_each = rule.value.expiration == null ? [] : [rule.value.expiration]
        content {
          days = expiration.value.days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration == null ? [] : [rule.value.noncurrent_version_expiration]
        content {
          noncurrent_days = noncurrent_version_expiration.value.noncurrent_days
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload == null ? [] : [rule.value.abort_incomplete_multipart_upload]
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value.days_after_initiation
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.bucket]
}

resource "aws_s3_bucket_object_lock_configuration" "bucket" {
  count = var.object_lock_configuration == null ? 0 : 1

  bucket = aws_s3_bucket.bucket.id

  rule {
    default_retention {
      mode  = var.object_lock_configuration.rule.default_retention.mode
      days  = var.object_lock_configuration.rule.default_retention.days
      years = var.object_lock_configuration.rule.default_retention.years
    }
  }

  depends_on = [aws_s3_bucket_versioning.bucket]
}

resource "aws_s3_bucket_cors_configuration" "bucket" {
  count = length(var.cors_rule) > 0 ? 1 : 0

  bucket = aws_s3_bucket.bucket.id

  dynamic "cors_rule" {
    for_each = var.cors_rule
    content {
      id              = cors_rule.value.id
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

resource "aws_s3_bucket_policy" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.bucket.arn, "${aws_s3_bucket.bucket.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }], var.policy_statements)
  })

  depends_on = [aws_s3_bucket_public_access_block.bucket]
}
