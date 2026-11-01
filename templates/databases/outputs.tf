output "databases" {
  description = "Database name -> its endpoint and the secret holding its admin password."
  value       = { for name, d in module.rds_instance : name => { endpoint = d.endpoint, password_secret_arn = d.password_secret_arn } }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The database files are not usable: ${join("; ", local.problems)}."
  }
}
