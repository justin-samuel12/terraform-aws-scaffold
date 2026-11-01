module "ssm_document" {
  source = "../../modules/ssm-document"

  documents = { for name, d in local.documents : name => { type = d.type, content = d.content } }
}
