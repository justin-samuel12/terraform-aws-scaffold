mock_provider "aws" {}

variables {
  environment = "staging"
  associations = {
    windows = {
      targets             = [{ key = "tag:Domain", values = ["aadds.example.com"] }]
      parameters          = { DomainName = "aadds.example.com", OrganizationalUnit = "OU=Staging,OU=AADDC Computers,DC=aadds,DC=example,DC=com" }
      schedule_expression = "rate(1 day)"
    }
  }
}

run "joins_by_tag" {
  command = plan

  assert {
    condition     = aws_ssm_association.join["windows"].name == "staging-DomainJoin" && aws_ssm_association.join["windows"].association_name == "staging-windows" && aws_ssm_association.join["windows"].parameters.SecretId == "domain-join/staging"
    error_message = "The association runs the environment's document on the servers its tag names, with the environment's join secret."
  }

  assert {
    condition     = aws_secretsmanager_secret.join[0].name == "domain-join/staging" && length(module.document) == 1
    error_message = "One join secret and one document per environment."
  }

  assert {
    condition     = strcontains(jsonencode(local.content.mainSteps[0].inputs.runCommand), "Add-Computer @join") && local.content.mainSteps[0].precondition.StringEquals[1] == "Windows"
    error_message = "The document runs the join script, on Windows only."
  }
}

run "nothing_without_an_association" {
  command = plan

  variables {
    associations = {}
  }

  assert {
    condition     = length(aws_secretsmanager_secret.join) == 0 && length(module.document) == 0
    error_message = "With no association, nothing is built."
  }
}

run "rejects_every_instance" {
  command = plan

  variables {
    associations = {
      windows = {
        targets    = [{ key = "InstanceIds", values = ["*"] }]
        parameters = { DomainName = "aadds.example.com", OrganizationalUnit = "OU=Staging,DC=aadds,DC=example,DC=com" }
      }
    }
  }

  expect_failures = [var.associations]
}

run "rejects_a_secret_of_its_own" {
  command = plan

  variables {
    associations = {
      windows = {
        targets    = [{ key = "tag:Domain", values = ["aadds.example.com"] }]
        parameters = { DomainName = "aadds.example.com", OrganizationalUnit = "OU=Staging,DC=aadds,DC=example,DC=com", SecretId = "admin" }
      }
    }
  }

  expect_failures = [var.associations]
}
