resource "aws_s3_bucket" "state" {
  bucket = var.bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

data "aws_iam_policy_document" "state" {
  source_policy_documents = [data.aws_iam_policy_document.tls_only["state"].json]

  dynamic "statement" {
    for_each = var.account_prefixes
    content {
      sid       = "ListOwnKeys${statement.key}"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [aws_s3_bucket.state.arn]

      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${statement.key}:root"]
      }

      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = concat(statement.value, ["env:/*"])
      }
    }
  }

  dynamic "statement" {
    for_each = var.account_prefixes
    content {
      sid       = "ReadWriteOwnKeys${statement.key}"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = [for p in statement.value : "${aws_s3_bucket.state.arn}/${p}"]

      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${statement.key}:root"]
      }
    }
  }
}

data "aws_iam_policy_document" "tls_only" {
  for_each = merge({ state = aws_s3_bucket.state.arn }, var.replica_region == null ? {} : { replica = aws_s3_bucket.replica[0].arn })

  statement {
    sid     = "RefuseAnythingNotOverTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      each.value,
      "${each.value}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket" "replica" {
  provider = aws.replica
  count    = var.replica_region == null ? 0 : 1

  bucket = "${var.bucket}-${var.replica_region}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.replica
  count    = var.replica_region == null ? 0 : 1

  bucket = aws_s3_bucket.replica[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  provider = aws.replica
  count    = var.replica_region == null ? 0 : 1

  bucket = aws_s3_bucket.replica[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider = aws.replica
  count    = var.replica_region == null ? 0 : 1

  bucket = aws_s3_bucket.replica[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "replica" {
  provider = aws.replica
  count    = var.replica_region == null ? 0 : 1

  bucket = aws_s3_bucket.replica[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "replica" {
  provider = aws.replica
  count    = var.replica_region == null ? 0 : 1

  bucket = aws_s3_bucket.replica[0].id
  policy = data.aws_iam_policy_document.tls_only["replica"].json

  depends_on = [aws_s3_bucket_public_access_block.replica]
}

data "aws_iam_policy_document" "replication_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "replication" {
  count = var.replica_region == null ? 0 : 1

  name               = "terraform-state-replication"
  description        = "S3 replicating Terraform state to ${var.replica_region}"
  assume_role_policy = data.aws_iam_policy_document.replication_trust.json
}

data "aws_iam_policy_document" "replication" {
  count = var.replica_region == null ? 0 : 1

  statement {
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.replica[0].arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication" {
  count = var.replica_region == null ? 0 : 1

  name   = "replicate-state"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "state" {
  count = var.replica_region == null ? 0 : 1

  bucket = aws_s3_bucket.state.id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "everything"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.replica[0].arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [aws_s3_bucket_versioning.state, aws_s3_bucket_versioning.replica]
}
