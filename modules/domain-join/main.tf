resource "aws_secretsmanager_secret" "join" {
  count = local.enabled ? 1 : 0

  name                    = local.secret_name
  description             = "The account ${var.environment}'s Windows servers join the domain with, as JSON with username and password. Set by a person: an account that may only create computers in the environment's OU, never an administrator."
  recovery_window_in_days = 30

  tags = { Name = "${local.name_prefix}Domain Join" }
}

module "document" {
  source = "../ssm-document"
  count  = local.enabled ? 1 : 0

  documents = { (local.document_name) = { type = "Command", content = local.content } }
}

resource "aws_ssm_association" "join" {
  for_each = local.enabled ? var.associations : {}

  name                = local.document_name
  association_name    = "${var.environment}-${each.key}"
  parameters          = merge(each.value.parameters, { SecretId = aws_secretsmanager_secret.join[0].name })
  schedule_expression = each.value.schedule_expression
  compliance_severity = each.value.compliance_severity
  max_concurrency     = each.value.max_concurrency
  max_errors          = each.value.max_errors

  dynamic "targets" {
    for_each = each.value.targets
    content {
      key    = targets.value.key
      values = targets.value.values
    }
  }

  depends_on = [module.document]
}
