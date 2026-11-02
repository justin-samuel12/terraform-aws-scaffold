module "ssm_document" {
  source = "../../modules/ssm-document"

  documents = { for name, d in local.documents : name => { type = d.document_type, content = d.content } }
}
