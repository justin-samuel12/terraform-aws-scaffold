output "databases" {
  description = "Database name -> its kind, endpoint (host:port), port, reader endpoint (Aurora) and the secret holding its admin password."
  value = merge(
    { for name, d in module.rds_instance : name => { kind = local.databases[name].kind, endpoint = d.endpoint, port = d.port, reader_endpoint = null, password_secret_arn = d.password_secret_arn } },
    { for name, d in module.rds_cluster : name => { kind = "aurora", endpoint = d.endpoint, port = d.port, reader_endpoint = d.reader_endpoint, password_secret_arn = d.password_secret_arn } },
  )

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The database files are not usable: ${join("; ", local.problems)}."
  }
}

output "rds_custom_instance_profile" {
  description = "The instance profile RDS Custom's servers run as, if there are any."
  value       = try(aws_iam_instance_profile.rds_custom[0].name, null)
}
