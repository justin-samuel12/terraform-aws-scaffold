locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }

  # Each file is a tunnel to one fixed host and port, so IAM can grant exactly that tunnel and nothing wider.
  documents = {
    for name, f in local.files : "${var.environment}-${name}" => {
      type = "Session"
      content = {
        schemaVersion = "1.0"
        description   = try(f.description, "Port forwarding to ${f.host}:${f.port}")
        sessionType   = "Port"
        parameters = {
          localPortNumber = { type = "String", description = "Port on your workstation", allowedPattern = "^[0-9]{1,5}$", default = tostring(try(f.local_port, f.port)) }
        }
        properties = {
          type            = "LocalPortForwarding"
          host            = f.host
          portNumber      = tostring(f.port)
          localPortNumber = "{{ localPortNumber }}"
        }
      }
    }
  }

  problems = [for name, f in local.files : "${name}.yml: needs host and port" if !can(f.host) || !can(f.port)]
}
