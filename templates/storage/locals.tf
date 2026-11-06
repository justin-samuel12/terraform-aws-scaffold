locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }

  file_keys         = ["tags", "mount_targets", "access_points"]
  mount_target_keys = ["subnet_id", "security_groups"]
  access_point_keys = ["posix_user", "root_directory", "tags"]

  file_systems = {
    for name, f in local.files : name => {
      tags = try(tomap(f.tags), {})
      mount_targets = [
        for m in(try(f.mount_targets, null) == null ? [] : try(tolist(f.mount_targets), [])) : {
          subnet_id       = try(tostring(m.subnet_id), "")
          security_groups = try([for g in tolist(m.security_groups) : tostring(g)], [])
        }
      ]
      access_points = {
        for ap, a in(try(f.access_points, null) == null ? {} : try(tomap(f.access_points), {})) : ap => {
          posix_user = try(a.posix_user, null) == null ? null : {
            uid            = try(tonumber(a.posix_user.uid), null)
            gid            = try(tonumber(a.posix_user.gid), null)
            secondary_gids = try(a.posix_user.secondary_gids, null) == null ? null : try([for g in tolist(a.posix_user.secondary_gids) : tonumber(g)], [])
          }
          root_directory = {
            path = try(tostring(a.root_directory.path), "")
            creation_info = try(a.root_directory.creation_info, null) == null ? null : {
              owner_uid   = try(tonumber(a.root_directory.creation_info.owner_uid), null)
              owner_gid   = try(tonumber(a.root_directory.creation_info.owner_gid), null)
              permissions = try(tostring(a.root_directory.creation_info.permissions), "")
            }
          }
          tags = try(tomap(a.tags), {})
        }
      }
    }
  }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a file system's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}: aws_efs_file_system's tags, its aws_efs_mount_target and aws_efs_access_point resources" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    flatten([for name, f in local.files : [
      for m in(try(f.mount_targets, null) == null ? [] : try(tolist(f.mount_targets), [])) : "${name}.yml: a mount target takes the arguments of aws_efs_mount_target: ${join(", ", local.mount_target_keys)}"
      if !can(keys(m)) || !alltrue([for k in try(keys(m), []) : contains(local.mount_target_keys, k)])
    ]]),
    flatten([for name, f in local.files : [
      for ap, a in(try(f.access_points, null) == null ? {} : try(tomap(f.access_points), {})) : "${name}.yml: access point ${ap} takes the arguments of aws_efs_access_point: ${join(", ", local.access_point_keys)}"
      if !can(keys(a)) || !alltrue([for k in try(keys(a), []) : contains(local.access_point_keys, k)])
    ]]),
    [for name, fs in local.file_systems : "${name}.yml: mount_targets lists one per zone, at least two and no subnet twice, each with subnet_id (a subnet's name, such as data-az1) and security_groups" if length(distinct([for m in fs.mount_targets : m.subnet_id])) != length(fs.mount_targets) || length(fs.mount_targets) < 2 || anytrue([for m in fs.mount_targets : m.subnet_id == "" || length(m.security_groups) == 0])],
    flatten([for name, fs in local.file_systems : [
      for ap, a in fs.access_points : "${name}.yml: access point ${ap} needs posix_user (uid, gid) and root_directory.path starting with /; creation_info, when written, needs owner_uid, owner_gid and octal permissions such as 0750"
      if a.posix_user == null || try(a.posix_user.uid, null) == null || try(a.posix_user.gid, null) == null || !startswith(a.root_directory.path, "/") || a.root_directory.creation_info != null && (try(a.root_directory.creation_info.owner_uid, null) == null || try(a.root_directory.creation_info.owner_gid, null) == null || !can(regex("^0[0-7]{3}$", try(a.root_directory.creation_info.permissions, ""))))
    ]]),
  )

  usable  = length(local.problems) == 0
  subnets = toset(flatten([for fs in values(local.file_systems) : [for m in fs.mount_targets : m.subnet_id if !startswith(m.subnet_id, "subnet-")]]))
  groups  = toset(flatten([for fs in values(local.file_systems) : [for m in fs.mount_targets : [for g in m.security_groups : g if !startswith(g, "sg-")]]]))
}
