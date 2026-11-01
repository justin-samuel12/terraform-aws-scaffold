output "file_systems" {
  description = "File system name -> its id and access point ids."
  value       = { for name, fs in module.efs_file_system : name => { id = fs.id, access_point_ids = fs.access_point_ids } }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The file system files are not usable: ${join("; ", local.problems)}."
  }
}
