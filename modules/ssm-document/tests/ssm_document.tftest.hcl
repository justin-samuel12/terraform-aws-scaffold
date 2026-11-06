mock_provider "aws" {}

variables {
  documents = {
    redis-tunnel = {
      type = "Session"
      content = {
        schemaVersion = "1.0"
        sessionType   = "Port"
        properties    = { type = "LocalPortForwarding", host = "redis.example.com", portNumber = "10701", localPortNumber = "10701" }
      }
    }
  }
}

run "session_document" {
  command = plan

  assert {
    condition     = aws_ssm_document.documents["redis-tunnel"].document_type == "Session" && yamldecode(aws_ssm_document.documents["redis-tunnel"].content).properties.host == "redis.example.com"
    error_message = "The document is written as YAML from its content."
  }
}

run "rejects_reserved_name" {
  command = plan

  variables {
    documents = { AWS-Mine = { type = "Command", content = {} } }
  }

  expect_failures = [var.documents]
}
