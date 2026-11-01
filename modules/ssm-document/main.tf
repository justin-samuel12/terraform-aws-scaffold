resource "aws_ssm_document" "documents" {
  for_each = var.documents

  name            = each.key
  document_type   = each.value.type
  document_format = "YAML"
  content         = yamlencode(each.value.content)

  tags = { Name = each.key }
}
