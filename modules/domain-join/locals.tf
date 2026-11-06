locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "
  enabled         = length(var.associations) > 0
  document_name   = "${var.environment}-DomainJoin"
  secret_name     = "domain-join/${var.environment}"

  content = {
    schemaVersion = "2.2"
    description   = "Join a Windows server to the domain, named after its Server tag, into one OU, with the environment's join account; does nothing on a member"
    parameters = {
      DomainName = {
        type           = "String"
        description    = "The domain's DNS name"
        allowedPattern = "^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"
      }
      OrganizationalUnit = {
        type           = "String"
        description    = "The OU the computer is created in"
        allowedPattern = "^(OU|CN)=[^'{}]+,DC=[^'{}]+$"
      }
      SecretId = {
        type           = "String"
        description    = "The secret holding the join account, as JSON with username and password"
        default        = local.secret_name
        allowedPattern = "^[A-Za-z0-9/_+=.@-]+$"
      }
    }
    mainSteps = [{
      action       = "aws:runPowerShellScript"
      name         = "join"
      precondition = { StringEquals = ["platformType", "Windows"] }
      inputs = {
        timeoutSeconds = "600"
        runCommand = concat(
          ["$DomainName = '{{ DomainName }}'", "$OrganizationalUnit = '{{ OrganizationalUnit }}'", "$SecretId = '{{ SecretId }}'"],
          split("\n", trimspace(file("${path.module}/domain-join.ps1"))),
        )
      }
    }]
  }
}
