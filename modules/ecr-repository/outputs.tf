output "urls" {
  description = "Repository name -> URL to push and pull."
  value       = { for name, repository in aws_ecr_repository.repositories : name => repository.repository_url }
}
