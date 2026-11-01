output "servers" {
  description = "Server name -> its subnet, chosen addresses (if any), and once built its instance id and private address."
  value = {
    for name, s in local.servers : name => merge(
      { subnet = s.subnet, chosen = s.addresses },
      try(module.ec2_instance[s.group].servers[name], {}),
    )
  }

  precondition {
    condition     = local.usable
    error_message = "The group files are not usable: ${join("; ", local.problems)}."
  }
}
