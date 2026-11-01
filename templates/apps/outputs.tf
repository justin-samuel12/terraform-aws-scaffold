output "applications" {
  description = "Application -> its servers, and the CodeDeploy application to deploy to (null when it is not deployed by CodeDeploy)."
  value       = { for app, a in module.application : app => { servers = a.servers, codedeploy_application = a.codedeploy_application } }

  precondition {
    condition     = local.usable
    error_message = "The application files are not usable: ${join("; ", local.problems)}."
  }
}
