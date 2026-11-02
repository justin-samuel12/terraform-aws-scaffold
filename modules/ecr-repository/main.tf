data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Tags cannot be overwritten, so a deployed tag always means the same image; every push is scanned.
resource "aws_ecr_repository" "repositories" {
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = each.key }
}

resource "aws_ecr_lifecycle_policy" "repositories" {
  for_each = var.repositories

  repository = aws_ecr_repository.repositories[each.key].name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Untagged images expire after ${var.untagged_days} days"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = var.untagged_days }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the newest ${var.keep_images} tagged images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.keep_images }
        action       = { type = "expire" }
      },
    ]
  })
}

resource "aws_ecr_replication_configuration" "registry" {
  count = length(var.replicate_to) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.replicate_to
        content {
          region      = destination.value
          registry_id = data.aws_caller_identity.current.account_id
        }
      }
    }
  }
}

# Other accounts pull, never push: their roles still need ecr:GetAuthorizationToken and the pull actions in IAM.
resource "aws_ecr_repository_policy" "pull" {
  for_each = length(var.pull_accounts) > 0 ? var.repositories : toset([])

  repository = aws_ecr_repository.repositories[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OtherAccountsPull"
      Effect    = "Allow"
      Principal = { AWS = [for a in sort(tolist(var.pull_accounts)) : "arn:${data.aws_partition.current.partition}:iam::${a}:root"] }
      Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    }]
  })
}

