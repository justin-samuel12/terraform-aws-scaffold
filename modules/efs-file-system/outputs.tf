output "id" {
  description = "The file system's id, for mounting."
  value       = aws_efs_file_system.file_system.id
}

output "access_point_ids" {
  description = "Access point name -> id."
  value       = { for name, ap in aws_efs_access_point.access_points : name => ap.id }
}
