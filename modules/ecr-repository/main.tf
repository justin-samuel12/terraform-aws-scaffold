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

  tags = merge(each.value.tags, { Name = "${local.name_prefix}${each.key}" })
}

resource "aws_ecr_lifecycle_policy" "repositories" {
  for_each = { for name, r in var.repositories : name => r if r.lifecycle_policy != null }

  repository = aws_ecr_repository.repositories[each.key].name
  policy     = each.value.lifecycle_policy
}

resource "aws_ecr_repository_policy" "repositories" {
  for_each = { for name, r in var.repositories : name => r if r.repository_policy != null }

  repository = aws_ecr_repository.repositories[each.key].name
  policy     = each.value.repository_policy
}

resource "aws_ecr_replication_configuration" "registry" {
  count = var.replication_configuration == null ? 0 : 1

  replication_configuration {
    dynamic "rule" {
      for_each = var.replication_configuration.rule
      content {
        dynamic "destination" {
          for_each = rule.value.destination
          content {
            region      = destination.value.region
            registry_id = destination.value.registry_id
          }
        }

        dynamic "repository_filter" {
          for_each = rule.value.repository_filter
          content {
            filter      = repository_filter.value.filter
            filter_type = repository_filter.value.filter_type
          }
        }
      }
    }
  }
}
